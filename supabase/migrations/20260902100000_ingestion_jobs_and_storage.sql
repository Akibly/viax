-- Day 2 — ingestion infrastructure: background jobs and private storage.
--
-- Audit OPS-03: the architecture draws upload -> OCR -> chunk -> embed as a
-- pipeline behind a POST, and pairs it with a status-polling endpoint that
-- implies async — but names no queue, worker or job runner anywhere in the
-- stack. A 300-page PDF exceeds any request timeout.
--
-- This is a Postgres-backed queue rather than a separate broker. For a
-- 15-day build with one developer, adding Redis or SQS buys throughput the
-- product does not need and costs an operational surface it cannot afford.
-- FOR UPDATE SKIP LOCKED is the standard, correct primitive.

create type public.job_status as enum ('queued', 'running', 'succeeded', 'failed', 'dead');

create type public.job_kind as enum ('extract', 'chunk', 'embed', 'extract_concepts');

create table public.ingestion_job (
  id             uuid primary key default gen_random_uuid(),
  document_id    uuid not null references public.document(id) on delete cascade,
  user_id        uuid not null references public.profile(id) on delete cascade,

  kind           public.job_kind   not null,
  status         public.job_status not null default 'queued',

  attempts       smallint not null default 0,
  max_attempts   smallint not null default 3,

  -- Exponential backoff. A worker only claims jobs whose time has come.
  run_after      timestamptz not null default now(),

  -- Set while a worker holds the job. A crashed worker leaves a stale lease
  -- that the reaper reclaims, rather than a job stuck running forever.
  leased_until   timestamptz,
  leased_by      text,

  error_code     text,
  error_message  text,

  -- Resumability: partial ingestion leaves usable chunks behind rather than
  -- rolling back. A retry picks up from here instead of re-embedding pages
  -- that already succeeded.
  cursor         jsonb not null default '{}'::jsonb,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  started_at     timestamptz,
  finished_at    timestamptz,

  constraint job_attempts_sane check (attempts >= 0 and attempts <= max_attempts + 1),
  constraint job_lease_implies_running check (
    (status = 'running') = (leased_until is not null)
  ),
  constraint job_failure_explained check (
    status not in ('failed', 'dead') or error_code is not null
  )
);

-- One job of each kind per document. Re-queueing an already-queued document
-- is a no-op rather than a duplicate charge (the pipeline is idempotent by
-- construction, not by the caller remembering).
create unique index ingestion_job_unique_active
  on public.ingestion_job (document_id, kind)
  where status in ('queued', 'running');

-- The claim query's index. Partial, so it stays small as completed jobs
-- accumulate.
create index ingestion_job_claimable
  on public.ingestion_job (run_after, created_at)
  where status = 'queued';

create index ingestion_job_lease_idx on public.ingestion_job (leased_until)
  where status = 'running';
create index ingestion_job_document_idx on public.ingestion_job (document_id);
create index ingestion_job_user_idx on public.ingestion_job (user_id);

create trigger ingestion_job_touch
  before update on public.ingestion_job
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Claim one job.
--
-- SKIP LOCKED is what makes this safe with N workers: each transaction takes
-- a different row instead of queueing behind the same one. Without it, two
-- workers serialise and throughput collapses to one worker.
-- ---------------------------------------------------------------------------

create or replace function app.claim_job(
  worker_id     text,
  lease_seconds integer default 300,
  kinds         public.job_kind[] default null
)
returns public.ingestion_job
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed public.ingestion_job;
begin
  update public.ingestion_job j
     set status       = 'running',
         attempts     = j.attempts + 1,
         leased_until = now() + make_interval(secs => lease_seconds),
         leased_by    = worker_id,
         started_at   = coalesce(j.started_at, now())
   where j.id = (
     select c.id
       from public.ingestion_job c
      where c.status = 'queued'
        and c.run_after <= now()
        and (kinds is null or c.kind = any(kinds))
      order by c.run_after, c.created_at
      for update skip locked
      limit 1
   )
  returning j.* into claimed;

  return claimed;
end;
$$;

-- ---------------------------------------------------------------------------
-- Reclaim jobs whose worker died mid-flight.
--
-- Without this a killed pod leaves documents stuck in `processing` forever,
-- which the student sees as an upload that never finishes.
-- ---------------------------------------------------------------------------

create or replace function app.reap_expired_leases()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  reclaimed integer;
begin
  with expired as (
    update public.ingestion_job j
       -- Both branches are cast explicitly: this function runs with an empty
       -- search_path, so bare literals resolve as text and the assignment
       -- fails with a datatype mismatch at runtime rather than at create time.
       set status       = case
                            when j.attempts >= j.max_attempts then 'dead'::public.job_status
                            else 'queued'::public.job_status
                          end,
           leased_until = null,
           leased_by    = null,
           run_after    = now() + make_interval(secs => least(300, power(2, j.attempts)::int * 15)),
           error_code   = coalesce(j.error_code, 'worker_lease_expired'),
           error_message = coalesce(j.error_message, 'Worker stopped responding; lease expired.')
     where j.status = 'running'
       and j.leased_until < now()
    returning j.id
  )
  select count(*)::int into reclaimed from expired;

  return reclaimed;
end;
$$;

-- ---------------------------------------------------------------------------
-- Private document storage.
--
-- Audit SEC-05: the corpus stores a "Supabase Storage path" and never states
-- bucket visibility. A public bucket makes every uploaded PDF world-readable
-- by URL, independent of any database policy — RLS on `document` would give
-- a false sense of protection while the file itself is open.
--
-- Objects are keyed <user_id>/<document_id>/<filename>, and the policies
-- below compare the first path segment to the caller.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documents',
  'documents',
  false,
  26214400,
  array['application/pdf',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'text/plain',
        'text/markdown',
        'image/png',
        'image/jpeg']
)
on conflict (id) do nothing;

create policy "own folder read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = (select app.current_user_id())::text
  );

create policy "own folder write" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = (select app.current_user_id())::text
  );

create policy "own folder delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = (select app.current_user_id())::text
  );

-- ---------------------------------------------------------------------------
-- RLS for the job table: a student may watch their own ingestion progress
-- and nothing else. Workers run as service_role.
-- ---------------------------------------------------------------------------

alter table public.ingestion_job enable row level security;

grant select on public.ingestion_job to authenticated;

create policy ingestion_job_select_own on public.ingestion_job
  for select to authenticated
  using (user_id = (select app.current_user_id()));

revoke all on function app.claim_job(text, integer, public.job_kind[]) from public, anon, authenticated;
revoke all on function app.reap_expired_leases() from public, anon, authenticated;
