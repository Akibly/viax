create table public.chat_space (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profile(id) on delete cascade,
  title text not null check (length(title) between 1 and 120),
  subject_id uuid references public.subject(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(id, user_id)
);
create table public.chat_turn (
  id uuid primary key,
  space_id uuid not null,
  user_id uuid not null default auth.uid(),
  prompt text not null check(length(prompt) between 1 and 6000),
  reply text not null check(length(reply) between 1 and 24000),
  sources jsonb not null default '[]',
  created_at timestamptz not null default now(),
  foreign key(space_id,user_id) references public.chat_space(id,user_id) on delete cascade
);
create index chat_turn_space_time on public.chat_turn(space_id,created_at);
alter table public.chat_space enable row level security;
alter table public.chat_turn enable row level security;
create policy chat_space_read on public.chat_space for select to authenticated using(user_id=auth.uid());
create policy chat_space_create on public.chat_space for insert to authenticated with check(
  user_id=auth.uid() and (subject_id is null or exists(select 1 from public.subject s where s.id=subject_id and s.user_id=auth.uid() and s.deleted_at is null))
);
create policy chat_space_delete on public.chat_space for delete to authenticated using(user_id=auth.uid());
create policy chat_turn_read on public.chat_turn for select to authenticated using(user_id=auth.uid());
create policy chat_turn_create on public.chat_turn for insert to authenticated with check(user_id=auth.uid());
grant select,insert,delete on public.chat_space to authenticated;
grant select,insert on public.chat_turn to authenticated;
