-- VivaX schema v1 — part 1/5: extensions, enumerated types, helpers
--
-- Design notes that differ from System Architecture §5, with reasons:
--
--   * There is no `user` table. Supabase owns `auth.users`; we key a `profile`
--     row to it. Creating a parallel user table is the classic Supabase
--     footgun (two sources of identity that drift).
--
--   * `gap_severity` gains `strong` and drops `none`. The corpus defined this
--     vocabulary three different ways (ADR-0001, C-05); this is the single
--     source of truth. Thresholds live in app.domain.mastery and every label
--     is derived from them.
--
--   * Embedding dimension is pinned at 1024 (bge-large / e5-large / voyage-3
--     class) and stored as `halfvec`. Half precision costs almost no recall and
--     roughly halves index memory; retrofitting quantisation onto a populated
--     table is painful, adopting it on day one is free.

create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "vector" with schema extensions;

-- ---------------------------------------------------------------------------
-- Enumerated types
-- ---------------------------------------------------------------------------

create type public.user_role as enum ('student', 'teacher');

create type public.document_status as enum ('pending', 'processing', 'ready', 'failed');

-- All four modes exist in the type from day one. Only `practice` and
-- `examination` are P0 (ADR-0001, C-01); enabling the others later is a
-- config change, not a migration.
create type public.viva_mode as enum ('practice', 'examination', 'professor', 'mock_interview');

-- `abandoned` and `expired` are not in the original spec. On mobile the
-- dominant outcome of a session is neither completed nor in-progress; without
-- these, abandoned sessions accumulate forever as in_progress (audit DB-07).
create type public.session_status as enum ('in_progress', 'completed', 'abandoned', 'expired');

create type public.input_mode as enum ('typed', 'voice');

create type public.gap_severity as enum ('strong', 'minor', 'medium', 'critical');

-- ---------------------------------------------------------------------------
-- Helper schema
-- ---------------------------------------------------------------------------

create schema if not exists app;
comment on schema app is 'Internal helper functions. Not exposed through PostgREST.';

revoke all on schema app from public, anon, authenticated;
grant usage on schema app to postgres, service_role;

-- Ownership check used by every RLS policy.
--
-- SECURITY DEFINER + a stable marking means the planner evaluates this once
-- per statement instead of once per row. The naive alternative — an EXISTS
-- subquery inside each policy — turns the hot retrieval path into a
-- correlated subquery per candidate row.
create or replace function app.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid();
$$;

comment on function app.current_user_id is
  'Current authenticated user, or NULL. Every RLS policy compares a denormalised user_id column against this.';

-- Standard updated_at trigger.
create or replace function app.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Blocks UPDATE and DELETE on append-only tables.
--
-- `evaluation` and `concept_mastery_event` are the two tables where mutation
-- destroys the product. Overwriting an evaluation makes a score unauditable;
-- overwriting a mastery value makes the improvement curve uncomputable
-- (audit DB-02). A trigger is used rather than relying on RLS because
-- service_role bypasses RLS.
create or replace function app.reject_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception
    'Table %.% is append-only; % is not permitted. Insert a correcting row instead.',
    tg_table_schema, tg_table_name, tg_op
    using errcode = 'restrict_violation';
end;
$$;
