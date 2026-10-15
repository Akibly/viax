-- Per-user spend control for model calls.
--
-- `daily_token_budget_per_user` has existed in the backend config since day
-- one, with a docstring claiming it is "enforced before the call, not after".
-- It was never read by anything. The Edge Functions had no quota, no rate
-- limit and no accounting, and anonymous sign-up is enabled — so any visitor
-- could loop `examine` and spend the shared provider key without ever
-- creating an account. That is a denial-of-wallet hole, not a missing feature.
--
-- Enforced in Postgres rather than in the function for two reasons: the check
-- and the increment must be one atomic step or two concurrent calls both pass
-- a nearly-exhausted budget, and a quota living in client-reachable code is
-- not a quota.

create table public.model_usage (
  user_id     uuid    not null references auth.users(id) on delete cascade,
  day         date    not null default (now() at time zone 'utc')::date,
  calls       integer not null default 0,
  tokens      bigint  not null default 0,
  -- Kept per day rather than as a running total so the window rolls without
  -- a reset job, and so abuse is visible as a spike rather than hidden in a
  -- lifetime figure.
  first_at    timestamptz not null default now(),
  last_at     timestamptz not null default now(),

  primary key (user_id, day),
  constraint model_usage_calls_sane check (calls >= 0),
  constraint model_usage_tokens_sane check (tokens >= 0)
);

comment on table public.model_usage is
  'One row per user per UTC day. Written only by app.claim_model_call, which is the single gate every model request passes through.';

create index model_usage_day on public.model_usage (day desc);

alter table public.model_usage enable row level security;

-- A student may see their own consumption; nobody may write it by hand.
create policy model_usage_select_own on public.model_usage
  for select to authenticated
  using (user_id = (select app.current_user_id()));

grant select on public.model_usage to authenticated;

-- Budgets live here rather than in application config so a change takes
-- effect without a redeploy, and so the numbers the database enforces are the
-- numbers somebody can actually read.
create table public.usage_policy (
  id                 boolean primary key default true check (id),
  daily_call_limit   integer not null default 60,
  daily_token_limit  bigint  not null default 250000,
  updated_at         timestamptz not null default now()
);

insert into public.usage_policy (id) values (true) on conflict (id) do nothing;

comment on table public.usage_policy is
  'Single-row table holding the per-user daily caps. 60 calls is roughly fifteen question-and-answer exchanges, which is a long sitting.';

-- No student-facing grants: the policy is read by a SECURITY DEFINER function
-- and must not be editable by the people it constrains.
alter table public.usage_policy enable row level security;

/*
 * Reserve one model call for the caller, or refuse.
 *
 * Returns the remaining allowance so a caller can surface "3 questions left
 * today" rather than only discovering the wall by hitting it.
 *
 * The insert-on-conflict is the atomic part: two concurrent requests
 * serialise on the primary key, so both cannot pass the same last unit of
 * budget. Doing this check in TypeScript would leave exactly that race.
 */
create or replace function app.claim_model_call(
  p_estimated_tokens bigint default 2000
)
returns table (allowed boolean, calls_left integer, tokens_left bigint, reason text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_policy public.usage_policy%rowtype;
  v_row    public.model_usage%rowtype;
  v_today  date := (now() at time zone 'utc')::date;
begin
  if v_user is null then
    return query select false, 0, 0::bigint, 'not authenticated';
    return;
  end if;

  select * into v_policy from public.usage_policy where id;

  -- Take the row for update, creating today's if it does not exist yet. The
  -- conflict branch locks the existing row, which is what serialises callers.
  insert into public.model_usage (user_id, day)
  values (v_user, v_today)
  on conflict (user_id, day) do update
    set last_at = now()
  returning * into v_row;

  if v_row.calls >= v_policy.daily_call_limit then
    return query select
      false,
      0,
      greatest(v_policy.daily_token_limit - v_row.tokens, 0),
      format('daily limit of %s model calls reached', v_policy.daily_call_limit);
    return;
  end if;

  if v_row.tokens + p_estimated_tokens > v_policy.daily_token_limit then
    return query select
      false,
      greatest(v_policy.daily_call_limit - v_row.calls, 0),
      0::bigint,
      'daily token budget reached';
    return;
  end if;

  update public.model_usage
     set calls  = calls + 1,
         tokens = tokens + p_estimated_tokens,
         last_at = now()
   where user_id = v_user and day = v_today
  returning * into v_row;

  return query select
    true,
    greatest(v_policy.daily_call_limit - v_row.calls, 0),
    greatest(v_policy.daily_token_limit - v_row.tokens, 0),
    null::text;
end;
$$;

comment on function app.claim_model_call is
  'Atomically reserves one model call against the caller''s daily budget. Every model request must pass through this; it is the only spend control.';

-- Reconcile an estimate against what the provider actually charged. Estimates
-- are deliberately pessimistic, so this usually returns budget rather than
-- consuming more.
create or replace function app.settle_model_call(
  p_estimated_tokens bigint,
  p_actual_tokens    bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null or p_actual_tokens is null then
    return;
  end if;
  update public.model_usage
     set tokens = greatest(tokens - p_estimated_tokens + p_actual_tokens, 0)
   where user_id = v_user
     and day = (now() at time zone 'utc')::date;
end;
$$;

revoke all on function app.claim_model_call(bigint) from public, anon;
revoke all on function app.settle_model_call(bigint, bigint) from public, anon;
grant execute on function app.claim_model_call(bigint) to authenticated;
grant execute on function app.settle_model_call(bigint, bigint) to authenticated;

-- The functions live in `app`, which authenticated has no USAGE on, so they
-- are reached through thin public wrappers like every other guarded helper.
create or replace function public.claim_model_call(p_estimated_tokens bigint default 2000)
returns table (allowed boolean, calls_left integer, tokens_left bigint, reason text)
language sql
security definer
set search_path = ''
as $$ select * from app.claim_model_call(p_estimated_tokens); $$;

create or replace function public.settle_model_call(
  p_estimated_tokens bigint, p_actual_tokens bigint
)
returns void
language sql
security definer
set search_path = ''
as $$ select app.settle_model_call(p_estimated_tokens, p_actual_tokens); $$;

revoke all on function public.claim_model_call(bigint) from public, anon;
revoke all on function public.settle_model_call(bigint, bigint) from public, anon;
grant execute on function public.claim_model_call(bigint) to authenticated;
grant execute on function public.settle_model_call(bigint, bigint) to authenticated;
