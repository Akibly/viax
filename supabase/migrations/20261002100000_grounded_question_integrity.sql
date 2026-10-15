-- A model-generated concept is not trusted until it carries an exact quote
-- from the student's source. Older concepts remain null until their document
-- is reprocessed, and the examiner will not use them in the meantime.
alter table public.concept
  add column if not exists source_evidence text;

alter table public.concept
  drop constraint if exists concept_source_evidence_not_blank;
alter table public.concept
  add constraint concept_source_evidence_not_blank
  check (source_evidence is null or length(btrim(source_evidence)) >= 24);

create or replace function app.source_contains_quote(p_source text, p_quote text)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select length(btrim(p_quote)) >= 24
    and strpos(
      lower(btrim(regexp_replace(normalize(p_source, NFKC), '\s+', ' ', 'g'))),
      lower(btrim(regexp_replace(normalize(p_quote, NFKC), '\s+', ' ', 'g')))
    ) > 0;
$$;
revoke all on function app.source_contains_quote(text, text) from public, anon, authenticated;

-- The examiner and readiness counter share one definition of a usable topic:
-- it must have verified quote provenance, a concept-to-chunk link, and an
-- embedded passage in a ready, visible document.
create or replace function public.grounded_concepts(p_subject_id uuid)
returns table (
  id uuid,
  canonical_name text,
  importance smallint,
  source_evidence text,
  description text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
      from public.subject s
     where s.id = p_subject_id
       and s.user_id = app.current_user_id()
       and s.deleted_at is null
  ) then
    raise exception 'subject not found' using errcode = '42501';
  end if;

  return query
    select distinct c.id, c.canonical_name, c.importance, c.source_evidence,
                    c.description
      from public.concept c
      join public.concept_chunk cc
        on cc.concept_id = c.id
       and cc.user_id = app.current_user_id()
      join public.chunk ch
        on ch.id = cc.chunk_id
       and ch.subject_id = p_subject_id
       and ch.user_id = app.current_user_id()
       and ch.embedding is not null
      join public.document d
        on d.id = ch.document_id
       and d.subject_id = p_subject_id
       and d.user_id = app.current_user_id()
       and d.status = 'ready'
       and d.deleted_at is null
     where c.subject_id = p_subject_id
       and c.user_id = app.current_user_id()
       and c.source_evidence is not null
       and length(btrim(c.source_evidence)) >= 24
       and app.source_contains_quote(ch.content, c.source_evidence)
     order by c.importance desc, c.canonical_name;
end;
$$;

revoke all on function public.grounded_concepts(uuid) from public, anon;
grant execute on function public.grounded_concepts(uuid) to authenticated;

-- Readiness must not count unsupported or orphaned concept rows as usable
-- study material.
create or replace function public.subject_readiness(p_subject_id uuid)
returns table (
  total_concepts integer,
  examined_concepts integer,
  coverage_pct numeric,
  mean_mastery numeric,
  mean_effective numeric,
  decay_loss numeric
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
      from public.subject s
     where s.id = p_subject_id
       and s.user_id = app.current_user_id()
       and s.deleted_at is null
  ) then
    raise exception 'subject not found' using errcode = '42501';
  end if;

  return query
    with grounded as (
      select distinct c.id
        from public.concept c
        join public.concept_chunk cc
          on cc.concept_id = c.id
         and cc.user_id = app.current_user_id()
        join public.chunk ch
          on ch.id = cc.chunk_id
         and ch.subject_id = p_subject_id
         and ch.user_id = app.current_user_id()
         and ch.embedding is not null
        join public.document d
          on d.id = ch.document_id
         and d.subject_id = p_subject_id
         and d.user_id = app.current_user_id()
         and d.status = 'ready'
         and d.deleted_at is null
       where c.subject_id = p_subject_id
         and c.user_id = app.current_user_id()
         and c.source_evidence is not null
         and length(btrim(c.source_evidence)) >= 24
         and app.source_contains_quote(ch.content, c.source_evidence)
    ),
    measured as (
      select g.id, cm.mastery_pct,
        app.decayed_mastery(cm.mastery_pct, cm.stability, cm.last_reviewed_at) as effective
        from grounded g
        left join public.concept_mastery cm
          on cm.concept_id = g.id
         and cm.subject_id = p_subject_id
         and cm.user_id = app.current_user_id()
    )
    select
      count(*)::integer,
      count(*) filter (where mastery_pct is not null)::integer,
      round(100.0 * count(*) filter (where mastery_pct is not null)
        / greatest(count(*), 1), 1),
      round(coalesce(avg(mastery_pct), 0), 1),
      round(coalesce(avg(effective), 0), 1),
      round(coalesce(avg(mastery_pct), 0) - coalesce(avg(effective), 0), 1)
      from measured;
end;
$$;

-- Retrieval now excludes pending, failed and soft-deleted documents, and a
-- concept filter is accepted only when the linked concept itself is verified
-- and belongs to the requested subject.
create or replace function app.hybrid_search(
  p_subject_id  uuid,
  p_query_text  text,
  p_query_embedding extensions.halfvec(1024),
  p_concept_ids uuid[] default null,
  p_limit       integer default 20,
  p_rrf_k       integer default 60
)
returns table (
  chunk_id       uuid,
  document_id    uuid,
  content        text,
  context_prefix text,
  page_number    integer,
  vector_rank    integer,
  lexical_rank   integer,
  fused_score    double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  with candidate as (
    select ch.id, ch.document_id, ch.content, ch.context_prefix,
           ch.page_number, ch.embedding, ch.fts
      from public.chunk ch
      join public.document d
        on d.id = ch.document_id
       and d.subject_id = p_subject_id
       and d.user_id = ch.user_id
       and d.status = 'ready'
       and d.deleted_at is null
     where ch.subject_id = p_subject_id
       and ch.embedding is not null
       and (
         p_concept_ids is null
         or cardinality(p_concept_ids) = 0
         or exists (
           select 1
             from public.concept_chunk cc
             join public.concept fc
               on fc.id = cc.concept_id
              and fc.subject_id = p_subject_id
              and fc.user_id = ch.user_id
              and fc.source_evidence is not null
            where cc.chunk_id = ch.id
              and cc.user_id = ch.user_id
              and cc.concept_id = any(p_concept_ids)
              and app.source_contains_quote(ch.content, fc.source_evidence)
         )
       )
  ),
  dense as (
    select id,
           row_number() over (
             order by embedding OPERATOR(extensions.<=>) p_query_embedding
           ) as rank
      from candidate
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
    left join dense d on d.id = c.id
    left join lexical l on l.id = c.id
   where d.rank is not null or l.rank is not null
   order by fused_score desc, c.id
   limit p_limit;
$$;

revoke all on function app.hybrid_search(
  uuid, text, extensions.halfvec, uuid[], integer, integer
) from public, anon, authenticated;
