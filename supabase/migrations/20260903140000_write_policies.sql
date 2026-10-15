-- Write policies for the authenticated student.
--
-- The original RLS migration wrote SELECT policies and stopped. That is
-- coherent only under an architecture where every write arrives through a
-- trusted server holding the service-role key, which bypasses RLS entirely.
-- Two things now write as the user instead:
--
--   * the app, which creates subjects and registers uploads;
--   * the ingest Edge Function, which deliberately runs under the caller's
--     JWT rather than the service role, so a bug in it cannot touch another
--     student's rows.
--
-- Under RLS, absence of a policy is denial. So every one of these tables
-- rejected every insert, and `revision_queue` — with no policy at all — was
-- unreachable in both directions.
--
-- The shape of each policy encodes what the row *is*:
--
--   * ownership is asserted with WITH CHECK on user_id, so a client cannot
--     write a row it would then be unable to read;
--   * examination records get INSERT but never UPDATE. A question asked and
--     an answer given are facts; letting them be edited after the mark is
--     seen would make the transcript worthless;
--   * the ownership triggers already installed (app.enforce_chunk_ownership
--     and friends) still run, and catch the case a policy cannot see: a row
--     you own pointed at a parent you do not.

-- Helper shorthand: every policy below compares against the same expression
-- the SELECT policies already use, so read and write agree by construction.

-- ── Documents ────────────────────────────────────────────────────────────
create policy document_insert_own on public.document
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

-- Status moves pending → extracting → … → ready, and soft deletion sets
-- deleted_at, so UPDATE is needed. The check re-asserts ownership so a row
-- cannot be handed to someone else mid-update.
create policy document_update_own on public.document
  for update to authenticated
  using (user_id = (select app.current_user_id()))
  with check (user_id = (select app.current_user_id()));

-- ── Ingestion output ─────────────────────────────────────────────────────
create policy chunk_insert_own on public.chunk
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

-- Re-ingesting a document must be able to clear what the last run produced.
create policy chunk_delete_own on public.chunk
  for delete to authenticated
  using (user_id = (select app.current_user_id()));

create policy concept_insert_own on public.concept
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy concept_update_own on public.concept
  for update to authenticated
  using (user_id = (select app.current_user_id()))
  with check (user_id = (select app.current_user_id()));

create policy concept_edge_insert_own on public.concept_edge
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy concept_edge_delete_own on public.concept_edge
  for delete to authenticated
  using (user_id = (select app.current_user_id()));

create policy concept_chunk_insert_own on public.concept_chunk
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy concept_chunk_delete_own on public.concept_chunk
  for delete to authenticated
  using (user_id = (select app.current_user_id()));

-- ── Mastery ──────────────────────────────────────────────────────────────
create policy concept_mastery_insert_own on public.concept_mastery
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy concept_mastery_update_own on public.concept_mastery
  for update to authenticated
  using (user_id = (select app.current_user_id()))
  with check (user_id = (select app.current_user_id()));

-- Append-only by design: the event log is what makes a mastery figure
-- explicable after the fact. No UPDATE, no DELETE.
create policy concept_mastery_event_insert_own on public.concept_mastery_event
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

-- ── Examination ──────────────────────────────────────────────────────────
create policy viva_session_insert_own on public.viva_session
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy viva_session_update_own on public.viva_session
  for update to authenticated
  using (user_id = (select app.current_user_id()))
  with check (user_id = (select app.current_user_id()));

create policy question_insert_own on public.question
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

-- No user_id of its own: it is scoped through the question it belongs to,
-- which the enforce_question_scope trigger also checks.
create policy question_source_chunk_insert_own on public.question_source_chunk
  for insert to authenticated
  with check (
    exists (
      select 1 from public.question q
       where q.id = question_id
         and q.user_id = (select app.current_user_id())
    )
  );

create policy answer_insert_own on public.answer
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy evaluation_insert_own on public.evaluation
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy evaluation_gap_insert_own on public.evaluation_gap
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

-- The citation trigger still verifies provenance: a gap may only cite a chunk
-- that actually grounded the question. This policy governs *whose* row it is;
-- that trigger governs whether it is honest.
create policy evaluation_citation_insert_own on public.evaluation_citation
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

-- ── Scheduling ───────────────────────────────────────────────────────────
-- `revision_queue` is a VIEW derived from concept_mastery, not a table: the
-- due buckets (today / tomorrow / this week) are computed from due_at in the
-- student's own timezone rather than stored. That is the fix for the original
-- enum design, and it means there is nothing here to write a policy for —
-- scheduling is changed by updating concept_mastery, which is covered above.

-- ── Ingestion jobs ───────────────────────────────────────────────────────
create policy ingestion_job_insert_own on public.ingestion_job
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy ingestion_job_update_own on public.ingestion_job
  for update to authenticated
  using (user_id = (select app.current_user_id()))
  with check (user_id = (select app.current_user_id()));
