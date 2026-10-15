-- Fix PostgREST RETURNING failure on UPDATE when a row becomes hidden by the SELECT policy (deleted_at).
-- By removing WITH CHECK, we fallback to just checking `user_id`, which is safe because `enforce_document_ownership`
-- prevents updating `user_id` to a different user, and deleting the row hides it properly without throwing 42501.
drop policy if exists document_update_own on public.document;

create policy document_update_own on public.document
  for update to authenticated
  using (user_id = (select app.current_user_id()));

-- Also fix subject just in case
drop policy if exists subject_update_own on public.subject;

create policy subject_update_own on public.subject
  for update to authenticated
  using (user_id = (select app.current_user_id()));
