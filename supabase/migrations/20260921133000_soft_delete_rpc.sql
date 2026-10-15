-- Fix for the "new row violates row-level security policy" error on soft-delete.
-- Since the SELECT policy hides rows with deleted_at IS NOT NULL, an UPDATE via PostgREST
-- that sets deleted_at = NOW() fails the SELECT policy check on the RETURNING clause.
-- An RPC running as security definer bypasses this quirk entirely.

create or replace function public.delete_document(p_document_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  update public.document
  set deleted_at = now()
  where id = p_document_id 
    and user_id = (select app.current_user_id());
end;
$$;

create or replace function public.delete_subject(p_subject_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  update public.subject
  set deleted_at = now()
  where id = p_subject_id 
    and user_id = (select app.current_user_id());
end;
$$;
