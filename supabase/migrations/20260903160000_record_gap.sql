-- Writing a gap and its citations atomically.
--
-- `evaluation_gap_must_be_cited` is a DEFERRABLE INITIALLY DEFERRED
-- constraint trigger: it fires at COMMIT and demands that the gap already has
-- at least one citation. That is exactly the right guarantee — a gap nobody
-- can trace to a passage is an unsourced accusation against a student — and
-- it works when the gap and its citations are written in one transaction.
--
-- PostgREST gives each `.insert()` its own transaction. So the gap committed
-- alone, the deferred trigger fired with no citations present, and every gap
-- insert failed. The API and the schema disagreed about transaction
-- boundaries, and the failure was invisible because the caller treated it as
-- "this gap had no citation" and moved on.
--
-- This function restores the single transaction the trigger was designed for.
-- Nothing is relaxed: cite a chunk that did not ground the question and
-- `verify_citation_provenance` still rejects the whole call.

create or replace function public.record_gap(
  p_evaluation_id uuid,
  p_label text,
  p_detail text,
  p_chunk_ids uuid[]
)
returns uuid
language plpgsql
security invoker           -- RLS applies; this is a convenience, not a bypass
set search_path = ''
as $$
declare
  v_user uuid := app.current_user_id();
  v_gap uuid;
begin
  if p_chunk_ids is null or cardinality(p_chunk_ids) = 0 then
    raise exception 'a gap must cite at least one chunk'
      using errcode = 'integrity_constraint_violation';
  end if;

  insert into public.evaluation_gap (evaluation_id, user_id, label, detail)
  values (p_evaluation_id, v_user, left(p_label, 200), left(p_detail, 2000))
  returning id into v_gap;

  insert into public.evaluation_citation (gap_id, chunk_id, user_id)
  select v_gap, chunk_id, v_user
    from unnest(p_chunk_ids) as chunk_id;

  -- Both rows are now in the same transaction, so the deferred check at
  -- commit sees the citations it was always asking for.
  return v_gap;
end;
$$;

comment on function public.record_gap is
  'Inserts an evaluation gap together with its citations in one transaction, which is what the deferred evaluation_gap_must_be_cited trigger requires. Provenance is still enforced by verify_citation_provenance.';

revoke all on function public.record_gap(uuid, text, text, uuid[]) from public, anon;
grant execute on function public.record_gap(uuid, text, text, uuid[]) to authenticated;
