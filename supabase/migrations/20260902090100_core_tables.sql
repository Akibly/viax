-- VivaX schema v1 — part 2/5: identity, subjects, documents, chunks
--
-- Every table below carries a denormalised `user_id`. This is deliberate and
-- it is the single most load-bearing decision in the schema.
--
-- System Architecture §5.4 gives `chunk` only a `document_id`. Enforcing
-- ownership then requires walking chunk -> document -> subject -> user on the
-- hottest query in the product, inside an RLS policy, per candidate row
-- (audit DB-05). One denormalised column turns that into an index lookup.
-- The cost is that the column must be kept true, which is enforced by trigger
-- rather than by convention.

-- ---------------------------------------------------------------------------
-- profile
-- ---------------------------------------------------------------------------

create table public.profile (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text        not null,
  display_name  text,
  role          public.user_role not null default 'student',

  -- Anchors the revision schedule. FSRS answers "when should this be
  -- reviewed"; the exam date answers "and is that soon enough". Without it
  -- the planner cannot compress intervals as the viva approaches.
  exam_date     date,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.profile is
  'Application-side user record, keyed to auth.users. Supabase owns identity; this owns product state.';

create trigger profile_touch
  before update on public.profile
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- subject
-- ---------------------------------------------------------------------------

create table public.subject (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profile(id) on delete cascade,
  name        text not null,
  description text,
  exam_date   date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  -- Soft delete. SRS FR-2.1 requires deletion, but a hard delete cascades a
  -- student's entire assessment history into nothing. Deletion hides; a
  -- separate erasure path (DPDP / account deletion) genuinely removes.
  deleted_at  timestamptz,

  constraint subject_name_not_blank check (length(btrim(name)) > 0)
);

-- "Operating Systems" five times over is a support burden and it fragments
-- the concept graph. Case-insensitive, and only among live rows.
create unique index subject_unique_name_per_user
  on public.subject (user_id, lower(btrim(name)))
  where deleted_at is null;

create index subject_user_idx on public.subject (user_id) where deleted_at is null;

create trigger subject_touch
  before update on public.subject
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- document
-- ---------------------------------------------------------------------------

create table public.document (
  id            uuid primary key default gen_random_uuid(),
  subject_id    uuid not null references public.subject(id) on delete cascade,
  user_id       uuid not null references public.profile(id) on delete cascade,

  filename      text not null,
  storage_path  text not null,
  mime_type     text not null,
  byte_size     bigint not null,
  page_count    integer,

  -- Re-uploading the same PDF is common (students re-sync from Drive).
  -- Hashing avoids paying for OCR and embeddings twice.
  content_hash  text not null,

  status        public.document_status not null default 'pending',

  -- The PRD names low-quality scans as a risk and promises "a clear
  -- processing-failed state rather than a silent bad result" — but the
  -- specified schema has nowhere to put the reason (audit RAG-04).
  -- "This PDF has no text layer" and "this photo is too blurry" need
  -- different advice.
  error_code    text,
  error_message text,

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  processed_at  timestamptz,
  deleted_at    timestamptz,

  -- ADR-0001, C-11: the corpus specified a 100 MB limit while also requiring
  -- the project run inside free-tier quotas. Those are incoherent by about
  -- two orders of magnitude.
  constraint document_size_limit  check (byte_size > 0 and byte_size <= 26214400),
  constraint document_page_limit  check (page_count is null or page_count between 1 and 300),
  constraint document_failure_explained check (
    status <> 'failed' or error_code is not null
  )
);

create unique index document_unique_content_per_subject
  on public.document (subject_id, content_hash)
  where deleted_at is null;

create index document_subject_idx on public.document (subject_id) where deleted_at is null;
create index document_user_idx    on public.document (user_id)    where deleted_at is null;
create index document_pending_idx on public.document (status, created_at)
  where status in ('pending', 'processing');

create trigger document_touch
  before update on public.document
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- chunk
-- ---------------------------------------------------------------------------

create table public.chunk (
  id            uuid primary key default gen_random_uuid(),
  document_id   uuid not null references public.document(id) on delete cascade,
  subject_id    uuid not null references public.subject(id)  on delete cascade,
  user_id       uuid not null references public.profile(id)  on delete cascade,

  chunk_index   integer not null,
  content       text    not null,

  -- Contextual retrieval: a short generated sentence situating the chunk in
  -- its document, prepended before embedding. An isolated chunk reading
  -- "the four conditions are..." does not retrieve for "deadlock" without it.
  context_prefix text,

  page_number   integer,
  token_count   integer,

  embedding     extensions.halfvec(1024),

  -- Lexical half of hybrid retrieval. Student engineering notes are short and
  -- acronym-dense (TLB, MMU, semaphore) — exactly the corpus where pure dense
  -- retrieval underperforms because embeddings blur exact technical terms
  -- (audit RAG-01).
  fts           tsvector generated always as (
                  to_tsvector('english', coalesce(context_prefix, '') || ' ' || content)
                ) stored,

  created_at    timestamptz not null default now(),

  constraint chunk_index_non_negative check (chunk_index >= 0),
  constraint chunk_content_not_blank  check (length(btrim(content)) > 0)
);

-- Ordering, and neighbour expansion when a retrieved chunk needs its context.
create unique index chunk_unique_position on public.chunk (document_id, chunk_index);

create index chunk_subject_idx on public.chunk (subject_id);
create index chunk_user_idx    on public.chunk (user_id);

comment on column public.chunk.embedding is
  'halfvec(1024). NULL until the embedding job completes — partial ingestion leaves usable rows behind rather than rolling back.';

-- ---------------------------------------------------------------------------
-- Denormalisation integrity
--
-- The denormalised user_id / subject_id columns are only safe if they cannot
-- disagree with the parent row. Enforced here rather than trusted to the
-- application, because an RLS policy reads them.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_document_ownership()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  owner uuid;
begin
  select s.user_id into owner from public.subject s where s.id = new.subject_id;
  if owner is null then
    raise exception 'Subject % does not exist', new.subject_id using errcode = 'foreign_key_violation';
  end if;
  if new.user_id <> owner then
    raise exception 'document.user_id (%) does not match owner of subject % (%)',
      new.user_id, new.subject_id, owner using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger document_ownership_consistent
  before insert or update of subject_id, user_id on public.document
  for each row execute function app.enforce_document_ownership();

create or replace function app.enforce_chunk_ownership()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent record;
begin
  select d.subject_id, d.user_id into parent
  from public.document d where d.id = new.document_id;

  if parent is null then
    raise exception 'Document % does not exist', new.document_id using errcode = 'foreign_key_violation';
  end if;
  if new.subject_id <> parent.subject_id or new.user_id <> parent.user_id then
    raise exception 'chunk ownership (subject %, user %) disagrees with document % (subject %, user %)',
      new.subject_id, new.user_id, new.document_id, parent.subject_id, parent.user_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger chunk_ownership_consistent
  before insert or update of document_id, subject_id, user_id on public.chunk
  for each row execute function app.enforce_chunk_ownership();
