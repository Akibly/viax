-- Safe access to retrieval.
--
-- `app.hybrid_search` and `app.subject_coverage` are SECURITY DEFINER, so
-- they run with the owner's rights and RLS does not apply inside them. Their
-- bodies filter on `subject_id` alone and never check who is asking. Granting
-- EXECUTE directly would therefore let any authenticated student read any
-- other student's notes by supplying a subject uuid — the single worst
-- failure this product could have.
--
-- The previous migration avoided that by revoking EXECUTE from everyone,
-- which is safe and also makes retrieval unreachable: the app cannot ask a
-- question grounded in the notes it just ingested.
--
-- These wrappers close the gap the right way round. Ownership is proven
-- first, against `public.subject` under the *caller's* identity, and only
-- then is the search delegated. The inner functions stay revoked, so this is
-- the only door and it has a lock on it.

create or replace function public.search_notes(
  p_subject_id uuid,
  p_query_text text,
  p_query_embedding text,
  p_concept_ids uuid[] default null,
  p_limit integer default 8
)
returns table (
  chunk_id uuid,
  document_id uuid,
  content text,
  context_prefix text,
  page_number integer,
  vector_rank integer,
  lexical_rank integer,
  fused_score double precision
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The ownership proof. `app.current_user_id()` reads the caller's JWT, so
  -- this cannot be spoofed by passing a different subject id.
  if not exists (
    select 1
      from public.subject s
     where s.id = p_subject_id
       and s.user_id = app.current_user_id()
       and s.deleted_at is null
  ) then
    raise exception 'subject not found' using errcode = '42501';
  end if;

  -- The embedding arrives as a JSON array of numbers, because PostgREST has
  -- no halfvec representation to send. Cast at the boundary.
  return query
    select *
      from app.hybrid_search(
        p_subject_id,
        p_query_text,
        p_query_embedding::extensions.halfvec(1024),
        p_concept_ids,
        p_limit,
        60
      );
end;
$$;

comment on function public.search_notes is
  'Ownership-checked wrapper over app.hybrid_search. The inner function is SECURITY DEFINER and has no ownership test of its own, so it stays revoked and this is the only route to it.';

create or replace function public.subject_readiness(p_subject_id uuid)
returns table (
  total_concepts integer,
  examined_concepts integer,
  coverage_pct numeric,
  mean_mastery numeric
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
    select
      count(*)::integer,
      count(*) filter (where cm.mastery_pct is not null)::integer,
      round(
        100.0 * count(*) filter (where cm.mastery_pct is not null)
        / greatest(count(*), 1), 1
      ),
      round(coalesce(avg(cm.mastery_pct), 0), 1)
      from public.concept c
      left join public.concept_mastery cm on cm.concept_id = c.id
     where c.subject_id = p_subject_id;
end;
$$;

comment on function public.subject_readiness is
  'Concept coverage and mean mastery for one owned subject. Counts concepts that have never been examined separately, because an absence of evidence is not a low score.';

revoke all on function public.search_notes(uuid, text, text, uuid[], integer) from public, anon;
revoke all on function public.subject_readiness(uuid) from public, anon;

grant execute on function public.search_notes(uuid, text, text, uuid[], integer) to authenticated;
grant execute on function public.subject_readiness(uuid) to authenticated;
