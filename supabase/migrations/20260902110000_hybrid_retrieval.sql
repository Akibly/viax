-- Day 3 — hybrid retrieval.
--
-- Audit RAG-01: the specified pipeline was embed -> top-k cosine. Student
-- engineering notes are short, jargon-dense and acronym-heavy (TLB, MMU,
-- semaphore, Banker's Algorithm). That is precisely the corpus where pure
-- dense retrieval underperforms, because exact technical-term matching is
-- what matters and embeddings blur it. Ask a vector index for "TLB" and it
-- will happily return a passage about caches that never says TLB.
--
-- Reciprocal Rank Fusion is used rather than a weighted score blend because
-- cosine similarity and ts_rank are not on comparable scales, and any fixed
-- weighting between them is a constant someone tuned once on one corpus.
-- RRF only reads *positions*, so it needs no calibration and cannot be
-- skewed by one retriever's score distribution.
--
--   score(d) = sum over retrievers of 1 / (k + rank(d))
--
-- k = 60 is the value from the original RRF paper and the de-facto default;
-- it damps the influence of the top rank enough that a document appearing
-- respectably in both lists beats one that tops a single list.

create or replace function app.hybrid_search(
  p_subject_id  uuid,
  p_query_text  text,
  p_query_embedding extensions.halfvec(1024),
  p_concept_ids uuid[] default null,
  p_limit       integer default 20,
  p_rrf_k       integer default 60
)
returns table (
  chunk_id      uuid,
  document_id   uuid,
  content       text,
  context_prefix text,
  page_number   integer,
  vector_rank   integer,
  lexical_rank  integer,
  fused_score   double precision
)
language sql
stable
security definer
-- search_path is empty so a caller cannot shadow a table or function this
-- SECURITY DEFINER body resolves. pg_catalog is still searched implicitly,
-- so built-ins are fine, but pgvector's operators live in `extensions` and
-- must be named explicitly: OPERATOR(extensions.<=>) rather than <=>.
set search_path = ''
as $$
  with candidate as (
    select c.id, c.document_id, c.content, c.context_prefix, c.page_number, c.embedding, c.fts
      from public.chunk c
     where c.subject_id = p_subject_id
       and c.embedding is not null
       -- Concept scoping. The PRD's own success metric is Concept Graph ->
       -- focused practice in one tap, which is unreachable unless retrieval
       -- can be narrowed to a concept (audit C-12 / API-03).
       and (
         p_concept_ids is null
         or cardinality(p_concept_ids) = 0
         or exists (
           select 1 from public.concept_chunk cc
            where cc.chunk_id = c.id and cc.concept_id = any(p_concept_ids)
         )
       )
  ),
  dense as (
    select id,
           row_number() over (order by embedding OPERATOR(extensions.<=>) p_query_embedding) as rank
      from candidate
     -- Over-fetch relative to p_limit so fusion has something to fuse: a
     -- document ranked 30th by vectors and 2nd by keywords is exactly the
     -- kind of hit hybrid search exists to rescue.
     order by embedding OPERATOR(extensions.<=>) p_query_embedding
     limit greatest(p_limit * 3, 30)
  ),
  lexical as (
    select id,
           row_number() over (
             order by ts_rank_cd(fts, websearch_to_tsquery('english', p_query_text)) desc
           ) as rank
      from candidate
     where fts @@ websearch_to_tsquery('english', p_query_text)
     order by ts_rank_cd(fts, websearch_to_tsquery('english', p_query_text)) desc
     limit greatest(p_limit * 3, 30)
  )
  select c.id,
         c.document_id,
         c.content,
         c.context_prefix,
         c.page_number,
         d.rank::integer,
         l.rank::integer,
         coalesce(1.0 / (p_rrf_k + d.rank), 0.0)
       + coalesce(1.0 / (p_rrf_k + l.rank), 0.0) as fused_score
    from candidate c
    left join dense   d on d.id = c.id
    left join lexical l on l.id = c.id
   where d.rank is not null or l.rank is not null
   order by fused_score desc, c.id
   limit p_limit;
$$;

comment on function app.hybrid_search is
  'Vector + BM25 retrieval fused by Reciprocal Rank Fusion, scoped to one subject and optionally to specific concepts.';

revoke all on function app.hybrid_search(uuid, text, extensions.halfvec, uuid[], integer, integer)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Corpus coverage, for the "insufficient material" guard.
--
-- Audit AI-07: FR-3.1 requires questions grounded *only* in uploaded
-- material. A student who uploads three pages will still be asked ten
-- questions, and the model will fill the gap from parametric knowledge —
-- silently violating the one requirement that separates this product from a
-- generic chatbot. Refusing to start is the honest behaviour, and it needs a
-- number to refuse on.
-- ---------------------------------------------------------------------------

create or replace function app.subject_coverage(p_subject_id uuid)
returns table (
  ready_documents  integer,
  pending_documents integer,
  failed_documents integer,
  chunk_count      integer,
  embedded_count   integer,
  concept_count    integer,
  total_tokens     bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*)::integer from public.document d
      where d.subject_id = p_subject_id and d.status = 'ready' and d.deleted_at is null),
    (select count(*)::integer from public.document d
      where d.subject_id = p_subject_id and d.status in ('pending','processing') and d.deleted_at is null),
    (select count(*)::integer from public.document d
      where d.subject_id = p_subject_id and d.status = 'failed' and d.deleted_at is null),
    (select count(*)::integer from public.chunk c where c.subject_id = p_subject_id),
    (select count(*)::integer from public.chunk c
      where c.subject_id = p_subject_id and c.embedding is not null),
    (select count(*)::integer from public.concept k where k.subject_id = p_subject_id),
    (select coalesce(sum(c.token_count), 0)::bigint from public.chunk c where c.subject_id = p_subject_id);
$$;

revoke all on function app.subject_coverage(uuid) from public, anon, authenticated;
