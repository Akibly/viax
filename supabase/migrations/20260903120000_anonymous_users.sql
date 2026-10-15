-- Anonymous users.
--
-- `profile.email` was NOT NULL because the original model assumed every user
-- arrives through email sign-up. Supabase's anonymous sign-in creates an
-- `auth.users` row with a NULL email, so `app.handle_new_user` violated the
-- constraint and the whole signup transaction rolled back — surfacing to the
-- client as an opaque "Database error creating anonymous user" 500.
--
-- Anonymous accounts matter here: every table is behind RLS keyed to
-- auth.uid(), so a student cannot upload a single note before authenticating.
-- Forcing sign-up before anyone can see the product work is the wrong trade,
-- and Supabase upgrades an anonymous user to a permanent one in place — the
-- uid never changes, so no rows move.
--
-- An anonymous user genuinely has no email address, so the column becomes
-- nullable rather than being filled with a synthetic one. A fabricated
-- placeholder would be indistinguishable from a real address in every query
-- that follows.

alter table public.profile
  alter column email drop not null;

comment on column public.profile.email is
  'NULL for anonymous accounts. Populated when the account is upgraded to a permanent one; the id is stable across that upgrade.';

-- Recreated so the display name degrades sensibly when there is no email to
-- derive one from.
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
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      -- split_part on NULL yields NULL, so guest accounts would otherwise
      -- land with no name at all and render as a blank row.
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Guest'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- An account that has notes must not be able to lose its identity: once an
-- email is set, it cannot be cleared back to anonymous.
create or replace function app.protect_profile_email()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.email is not null and new.email is null then
    raise exception 'profile.email cannot be cleared once set (id=%)', old.id
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists profile_email_is_one_way on public.profile;
create trigger profile_email_is_one_way
  before update on public.profile
  for each row execute function app.protect_profile_email();
