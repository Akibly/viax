-- VivaX schema v1 — part 5/5: Row-Level Security
--
-- Audit SEC-01: the word "RLS" appears zero times in the 33-page specification
-- corpus, while three documents promise per-student isolation. On Supabase,
-- isolation IS row-level security: a Flutter client holds the anon key and a
-- user JWT, and can read any table RLS does not protect. Uploaded lecture
-- notes are personal data.
--
-- POSTURE
--
--   anon           nothing. VivaX has no public content.
--   authenticated  reads its own rows; writes only where a write is a pure
--                  client concern (profile settings, subject CRUD).
--   service_role   bypasses RLS by design. The backend runs as service_role
--                  and is therefore responsible for scoping every query it
--                  makes. RLS is the second line, not the only one.
--
-- Everything else — chunks, questions, evaluations, mastery — is written by
-- the backend, because every one of those writes either costs money, touches
-- a job queue, or has an invariant the client cannot enforce. Granting the
-- client write access to them would be convenience bought with correctness.
--
-- A table with RLS enabled and no matching policy denies by default. That is
-- the intended state for anything not listed below.

-- ---------------------------------------------------------------------------
-- Baseline privileges
-- ---------------------------------------------------------------------------

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;

alter default privileges in schema public revoke all on tables from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere. No exceptions, no "we'll add it later".
-- ---------------------------------------------------------------------------

alter table public.profile               enable row level security;
alter table public.subject               enable row level security;
alter table public.document              enable row level security;
alter table public.chunk                 enable row level security;
alter table public.concept               enable row level security;
alter table public.concept_edge          enable row level security;
alter table public.concept_chunk         enable row level security;
alter table public.viva_session          enable row level security;
alter table public.question              enable row level security;
alter table public.question_source_chunk enable row level security;
alter table public.answer                enable row level security;
alter table public.evaluation            enable row level security;
alter table public.evaluation_gap        enable row level security;
alter table public.evaluation_citation   enable row level security;
alter table public.concept_mastery       enable row level security;
alter table public.concept_mastery_event enable row level security;

-- ---------------------------------------------------------------------------
-- profile — read and update own
-- ---------------------------------------------------------------------------

grant select, update (display_name, exam_date, timezone) on public.profile to authenticated;

create policy profile_select_own on public.profile
  for select to authenticated
  using (id = (select app.current_user_id()));

create policy profile_update_own on public.profile
  for update to authenticated
  using (id = (select app.current_user_id()))
  with check (id = (select app.current_user_id()));

-- ---------------------------------------------------------------------------
-- subject — full client CRUD except hard delete
--
-- SRS FR-2.1 requires create, rename and delete. Deletion is a soft delete
-- (set deleted_at) so a student's assessment history is not cascaded into
-- nothing by a mis-tap; genuine erasure runs through the account-deletion
-- path, which must also remove embeddings and storage objects.
-- ---------------------------------------------------------------------------

grant select, insert, update on public.subject to authenticated;

create policy subject_select_own on public.subject
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy subject_insert_own on public.subject
  for insert to authenticated
  with check (user_id = (select app.current_user_id()));

create policy subject_update_own on public.subject
  for update to authenticated
  using (user_id = (select app.current_user_id()))
  with check (user_id = (select app.current_user_id()));

-- ---------------------------------------------------------------------------
-- Read-only surfaces
--
-- Written by the backend as service_role; readable by their owner.
-- ---------------------------------------------------------------------------

grant select on public.document              to authenticated;
grant select on public.chunk                 to authenticated;
grant select on public.concept               to authenticated;
grant select on public.concept_edge          to authenticated;
grant select on public.concept_chunk         to authenticated;
grant select on public.viva_session          to authenticated;
grant select on public.question              to authenticated;
grant select on public.question_source_chunk to authenticated;
grant select on public.answer                to authenticated;
grant select on public.evaluation            to authenticated;
grant select on public.evaluation_gap        to authenticated;
grant select on public.evaluation_citation   to authenticated;
grant select on public.concept_mastery       to authenticated;
grant select on public.concept_mastery_event to authenticated;

create policy document_select_own on public.document
  for select to authenticated
  using (user_id = (select app.current_user_id()) and deleted_at is null);

create policy chunk_select_own on public.chunk
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy concept_select_own on public.concept
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy concept_edge_select_own on public.concept_edge
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy concept_chunk_select_own on public.concept_chunk
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy viva_session_select_own on public.viva_session
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy question_select_own on public.question
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy answer_select_own on public.answer
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy evaluation_select_own on public.evaluation
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy evaluation_gap_select_own on public.evaluation_gap
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy evaluation_citation_select_own on public.evaluation_citation
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy concept_mastery_select_own on public.concept_mastery
  for select to authenticated
  using (user_id = (select app.current_user_id()));

create policy mastery_event_select_own on public.concept_mastery_event
  for select to authenticated
  using (user_id = (select app.current_user_id()));

-- question_source_chunk has no user_id of its own. Rather than denormalise a
-- fourth column onto a pure join table, gate it on the parent question, which
-- is itself protected. This is the one place an EXISTS is acceptable: the
-- table is only read alongside a question already in hand.
create policy question_source_chunk_select_own on public.question_source_chunk
  for select to authenticated
  using (
    exists (
      select 1 from public.question q
      where q.id = question_source_chunk.question_id
        and q.user_id = (select app.current_user_id())
    )
  );

-- ---------------------------------------------------------------------------
-- Views inherit RLS from their base tables via security_invoker.
-- ---------------------------------------------------------------------------

grant select on public.revision_queue to authenticated;

-- ---------------------------------------------------------------------------
-- New users get a profile row automatically.
--
-- Without this the first authenticated request finds no profile and every
-- foreign key to profile(id) fails. Runs as definer because auth.users is
-- not writable by the app role.
-- ---------------------------------------------------------------------------

create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profile (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();
