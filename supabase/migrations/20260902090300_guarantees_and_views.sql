-- VivaX schema v1 — part 4/5: enforced guarantees, derived views, search indexes

-- ---------------------------------------------------------------------------
-- "Today" needs a timezone
--
-- The revision planner's buckets are Today / Tomorrow / Weekend / Before Exam.
-- Computed in UTC, a student in Gujarat gets a "today" that ends at 05:30
-- local. No document mentions timezone.
-- ---------------------------------------------------------------------------

alter table public.profile
  add column timezone text not null default 'UTC';

alter table public.profile
  add constraint profile_timezone_valid
  check (now() at time zone timezone is not null);

-- ---------------------------------------------------------------------------
-- Guarantee: every flagged gap carries at least one citation
--
-- The PRD's success metric is "100% of flagged gaps are cited". A metric
-- nobody enforces is an aspiration. This makes it a property of the database:
-- an uncited gap cannot be committed.
--
-- Deferred so the application can insert a gap and its citations in one
-- transaction, in either order.
-- ---------------------------------------------------------------------------

create or replace function app.require_gap_citation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.evaluation_citation c where c.gap_id = new.id
  ) then
    raise exception
      'Gap "%" (%) has no citation. Every flagged gap must cite at least one retrieved chunk.',
      new.label, new.id
      using errcode = 'integrity_constraint_violation';
  end if;
  return null;
end;
$$;

create constraint trigger evaluation_gap_must_be_cited
  after insert on public.evaluation_gap
  deferrable initially deferred
  for each row execute function app.require_gap_citation();

-- ---------------------------------------------------------------------------
-- Guarantee: a citation must point at a chunk that was actually retrieved
--
-- This is the structural half of the anti-hallucination design. The model is
-- given an enumerated set of chunk IDs and may cite only those; here we
-- verify the cited chunk was among the sources grounding the question that
-- was asked. A fabricated citation fails a constraint rather than reaching a
-- student who can check page 42.
-- ---------------------------------------------------------------------------

create or replace function app.verify_citation_provenance()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  q_id uuid;
  ok   boolean;
begin
  select q.id into q_id
  from public.evaluation_gap g
  join public.evaluation e on e.id = g.evaluation_id
  join public.answer     a on a.id = e.answer_id
  join public.question   q on q.id = a.question_id
  where g.id = new.gap_id;

  if q_id is null then
    raise exception 'Citation % references a gap with no resolvable question', new.id
      using errcode = 'foreign_key_violation';
  end if;

  select exists (
    select 1 from public.question_source_chunk qsc
    where qsc.question_id = q_id and qsc.chunk_id = new.chunk_id
  ) into ok;

  if not ok then
    raise exception
      'Chunk % was not retrieved for question % and cannot be cited. Citations are restricted to the grounding set.',
      new.chunk_id, q_id
      using errcode = 'integrity_constraint_violation';
  end if;

  return new;
end;
$$;

create trigger evaluation_citation_provenance
  before insert on public.evaluation_citation
  for each row execute function app.verify_citation_provenance();

-- ---------------------------------------------------------------------------
-- Guarantee: a question's concept must belong to the session's subject
-- ---------------------------------------------------------------------------

create or replace function app.enforce_question_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  s_subject uuid;
  s_user    uuid;
  c_subject uuid;
begin
  select vs.subject_id, vs.user_id into s_subject, s_user
  from public.viva_session vs where vs.id = new.session_id;

  select c.subject_id into c_subject
  from public.concept c where c.id = new.concept_id;

  if s_subject is null then
    raise exception 'Session % does not exist', new.session_id using errcode = 'foreign_key_violation';
  end if;
  if c_subject is distinct from s_subject then
    raise exception 'Concept % belongs to subject %, but the session is on subject %',
      new.concept_id, c_subject, s_subject using errcode = 'check_violation';
  end if;
  if new.user_id <> s_user then
    raise exception 'question.user_id does not match the session owner'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger question_scope_consistent
  before insert or update of session_id, concept_id, user_id on public.question
  for each row execute function app.enforce_question_scope();

-- ---------------------------------------------------------------------------
-- Derived view: the revision queue
--
-- The four planner tabs are views over due_at, not stored state. A row does
-- not need rewriting when a day passes; the bucket it falls into simply
-- changes, which is the whole point of DB-03.
-- ---------------------------------------------------------------------------

create or replace view public.revision_queue
with (security_invoker = true)
as
select
  cm.user_id,
  cm.subject_id,
  cm.concept_id,
  c.canonical_name        as concept_name,
  cm.mastery_pct,
  cm.gap_severity,
  cm.due_at,
  cm.stability,
  cm.review_count,
  s.exam_date,
  -- Rough time-to-review, scaled by how far the concept has to travel.
  greatest(5, least(45, round((100 - cm.mastery_pct) * 0.35)))::int as estimated_minutes,
  case
    when cm.due_at is null then 'unscheduled'
    when (cm.due_at at time zone p.timezone)::date
         <= (now() at time zone p.timezone)::date                          then 'today'
    when (cm.due_at at time zone p.timezone)::date
         =  (now() at time zone p.timezone)::date + 1                      then 'tomorrow'
    when (cm.due_at at time zone p.timezone)::date
         <= (now() at time zone p.timezone)::date
            + ((6 - extract(isodow from now() at time zone p.timezone))::int + 1)
                                                                           then 'weekend'
    when s.exam_date is not null
         and (cm.due_at at time zone p.timezone)::date <= s.exam_date       then 'before_exam'
    else 'later'
  end as bucket
from public.concept_mastery cm
join public.concept  c on c.id = cm.concept_id
join public.subject  s on s.id = cm.subject_id
join public.profile  p on p.id = cm.user_id
where s.deleted_at is null;

comment on view public.revision_queue is
  'Today / Tomorrow / Weekend / Before Exam derived from due_at in the user timezone. security_invoker means RLS on the base tables applies.';

-- ---------------------------------------------------------------------------
-- Search indexes
--
-- HNSW over IVFFlat: this is a continuous-ingest workload (students upload
-- throughout a term), which is where IVFFlat's need for a representative
-- training set hurts. Search quality is tuned at query time through
-- hnsw.ef_search, which needs no rebuild.
--
-- NOTE for operators: build these with maintenance_work_mem large enough to
-- hold the graph. If it spills to disk the build is 10-50x slower.
-- ---------------------------------------------------------------------------

create index chunk_embedding_hnsw
  on public.chunk
  using hnsw (embedding extensions.halfvec_cosine_ops)
  with (m = 16, ef_construction = 64);

create index chunk_fts_idx on public.chunk using gin (fts);

-- Retrieval is always scoped to one subject. A composite index lets the
-- planner narrow before it reaches the vector index.
create index chunk_subject_embedded_idx on public.chunk (subject_id)
  where embedding is not null;
