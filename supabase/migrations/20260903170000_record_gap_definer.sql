-- record_gap could not read the caller's identity.
--
-- It was SECURITY INVOKER, which is the safer default, but it calls
-- `app.current_user_id()` and the `authenticated` role has no USAGE on the
-- `app` schema — deliberately, since that schema holds SECURITY DEFINER
-- helpers that must not be callable directly. So every gap failed with
-- "permission denied for schema app", and the only visible symptom was an
-- evaluation with no gaps.
--
-- Granting USAGE on `app` to authenticated would fix the error and open every
-- helper in that schema to direct calls, including `hybrid_search`, which has
-- no ownership check of its own. That trade is not worth making.
--
-- Instead this follows the same shape as `public.search_notes`: run as
-- definer, and prove ownership explicitly before writing anything. Because
-- SECURITY DEFINER bypasses RLS, the ownership test is not a nicety here —
-- it is the whole protection, so it comes first and it names the caller from
-- auth.uid() rather than from any argument.

create or replace function public.record_gap(
  p_evaluation_id uuid,
  p_label text,
  p_detail text,
  p_chunk_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_gap uuid;
begin
  if v_user is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_chunk_ids is null or cardinality(p_chunk_ids) = 0 then
    raise exception 'a gap must cite at least one chunk'
      using errcode = 'integrity_constraint_violation';
  end if;

  -- RLS does not apply inside a definer function, so ownership of the target
  -- evaluation is checked here or not at all.
  if not exists (
    select 1
      from public.evaluation e
     where e.id = p_evaluation_id
       and e.user_id = v_user
  ) then
    raise exception 'evaluation not found' using errcode = '42501';
  end if;

  insert into public.evaluation_gap (evaluation_id, user_id, label, detail)
  values (p_evaluation_id, v_user, left(p_label, 200), left(p_detail, 2000))
  returning id into v_gap;

  -- Same transaction as the gap, which is what the deferred
  -- evaluation_gap_must_be_cited trigger requires. Provenance is still
  -- checked by verify_citation_provenance: a chunk that did not ground the
  -- question fails here and takes the whole call down with it.
  insert into public.evaluation_citation (gap_id, chunk_id, user_id)
  select v_gap, chunk_id, v_user
    from unnest(p_chunk_ids) as chunk_id;

  return v_gap;
end;
$$;

revoke all on function public.record_gap(uuid, text, text, uuid[]) from public, anon;
grant execute on function public.record_gap(uuid, text, text, uuid[]) to authenticated;
