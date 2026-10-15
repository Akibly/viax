-- VivaX schema v1 — part 3/5: concepts, sessions, evaluation, mastery
--
-- This file contains the four structures the audit found missing from
-- System Architecture §5, each of which breaks a headline feature by its
-- absence:
--
--   DB-01  `concept` + `question.concept_id`  — without these, nothing
--          connects an answer to a concept, so the mastery-update loop the
--          product is built on has no defined input.
--   DB-02  `concept_mastery_event`            — without history, the
--          improvement curve, "34% -> 51%", and predictive readiness are
--          uncomputable.
--   DB-03  FSRS fields on `concept_mastery`   — the spec stored the revision
--          schedule as an enum (today/tomorrow/weekend/before_exam), which
--          means "today" is wrong tomorrow.
--   DB-04  `evaluation_citation` as a foreign key — free-text citations
--          cannot be constrained to chunks that were actually retrieved.

-- ---------------------------------------------------------------------------
-- concept
-- ---------------------------------------------------------------------------

create table public.concept (
  id              uuid primary key default gen_random_uuid(),
  subject_id      uuid not null references public.subject(id) on delete cascade,
  user_id         uuid not null references public.profile(id) on delete cascade,

  canonical_name  text not null,

  -- Extraction will produce "Deadlock", "Deadlocks" and "Dead lock" from the
  -- same corpus. Aliases collapse them without losing the surface forms.
  aliases         text[] not null default '{}',

  description     text,

  -- Drives readiness weighting: a concept the notes spend twenty pages on
  -- should not count the same as one mentioned once.
  importance      smallint not null default 3,

  source_document_id uuid references public.document(id) on delete set null,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint concept_name_not_blank check (length(btrim(canonical_name)) > 0),
  constraint concept_importance_range check (importance between 1 and 5)
);

create unique index concept_unique_name_per_subject
  on public.concept (subject_id, lower(btrim(canonical_name)));

create index concept_subject_idx on public.concept (subject_id);
create index concept_user_idx    on public.concept (user_id);
create index concept_aliases_idx on public.concept using gin (aliases);

create trigger concept_touch
  before update on public.concept
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- concept_edge — what makes the Concept Graph a graph
--
-- Prerequisite edges are the difference between a bar chart of strings and a
-- diagnosis. They enable the one genuinely impressive claim in the product:
-- "you are failing Deadlock because you never learned Mutual Exclusion."
-- ---------------------------------------------------------------------------

create table public.concept_edge (
  id                      uuid primary key default gen_random_uuid(),
  subject_id              uuid not null references public.subject(id) on delete cascade,
  user_id                 uuid not null references public.profile(id) on delete cascade,
  prerequisite_concept_id uuid not null references public.concept(id) on delete cascade,
  dependent_concept_id    uuid not null references public.concept(id) on delete cascade,
  confidence              numeric(4,3) not null default 0.500,
  created_at              timestamptz not null default now(),

  constraint concept_edge_no_self_loop check (prerequisite_concept_id <> dependent_concept_id),
  constraint concept_edge_confidence_range check (confidence >= 0 and confidence <= 1)
);

create unique index concept_edge_unique
  on public.concept_edge (prerequisite_concept_id, dependent_concept_id);

create index concept_edge_dependent_idx on public.concept_edge (dependent_concept_id);
create index concept_edge_user_idx      on public.concept_edge (user_id);

-- ---------------------------------------------------------------------------
-- concept_chunk — which passages teach which concept
--
-- Required for concept-scoped sessions (ADR-0001, C-12): the PRD's own
-- success metric is Concept Graph -> focused practice in one tap, which needs
-- retrieval filtered to a concept.
-- ---------------------------------------------------------------------------

create table public.concept_chunk (
  concept_id uuid not null references public.concept(id) on delete cascade,
  chunk_id   uuid not null references public.chunk(id)   on delete cascade,
  user_id    uuid not null references public.profile(id) on delete cascade,
  relevance  numeric(4,3) not null default 0.500,
  primary key (concept_id, chunk_id),
  constraint concept_chunk_relevance_range check (relevance >= 0 and relevance <= 1)
);

create index concept_chunk_chunk_idx on public.concept_chunk (chunk_id);
create index concept_chunk_user_idx  on public.concept_chunk (user_id);

-- ---------------------------------------------------------------------------
-- viva_session
-- ---------------------------------------------------------------------------

create table public.viva_session (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profile(id) on delete cascade,
  subject_id            uuid not null references public.subject(id) on delete cascade,

  mode                  public.viva_mode    not null,
  status                public.session_status not null default 'in_progress',

  -- Concept-scoped sessions. Empty array means "the whole subject".
  focus_concept_ids     uuid[] not null default '{}',

  target_question_count smallint not null default 10,

  -- Which rubric and policy produced this session's scores. Without this an
  -- evaluation cannot be traced to the prompt that generated it, and a score
  -- distribution shift is indistinguishable from a change in student cohort
  -- (audit AI-08).
  rubric_version        text not null,
  policy_version        text not null,

  started_at            timestamptz not null default now(),
  ended_at              timestamptz,

  -- Powers resume: "Operating Systems, question 4 of 10, 20 minutes ago"
  -- (audit UX-02). Also drives the job that ages out abandoned sessions.
  last_activity_at      timestamptz not null default now(),

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint session_question_count_range check (target_question_count between 1 and 50),
  constraint session_ended_when_terminal check (
    (status = 'in_progress' and ended_at is null)
    or (status <> 'in_progress' and ended_at is not null)
  )
);

create index session_user_active_idx on public.viva_session (user_id, last_activity_at desc)
  where status = 'in_progress';
create index session_subject_idx on public.viva_session (subject_id, started_at desc);
create index session_stale_idx   on public.viva_session (last_activity_at)
  where status = 'in_progress';

create trigger viva_session_touch
  before update on public.viva_session
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- question
-- ---------------------------------------------------------------------------

create table public.question (
  id               uuid primary key default gen_random_uuid(),
  session_id       uuid not null references public.viva_session(id) on delete cascade,
  user_id          uuid not null references public.profile(id) on delete cascade,

  -- audit DB-01. Without this the evaluation has no way to decide which
  -- mastery row it should move.
  concept_id       uuid not null references public.concept(id) on delete restrict,

  -- Position within the session. The unique constraint below is what makes
  -- question creation idempotent: asking for question 4 twice returns the
  -- same row instead of generating (and paying for) another. The specified
  -- API used a mutating GET, which a mobile client will retry freely
  -- (audit API-01).
  ordinal          smallint not null,

  difficulty_level smallint not null,
  text             text not null,

  -- What a complete answer should contain. Given to the evaluator as the
  -- reference, and shown to the student in Practice mode.
  expected_points  text[] not null default '{}',

  prompt_version   text not null,
  model            text not null,

  created_at       timestamptz not null default now(),

  constraint question_difficulty_range check (difficulty_level between 1 and 5),
  constraint question_ordinal_positive  check (ordinal >= 1),
  constraint question_text_not_blank    check (length(btrim(text)) > 0)
);

create unique index question_unique_ordinal on public.question (session_id, ordinal);
create index question_concept_idx on public.question (concept_id);
create index question_user_idx    on public.question (user_id);

-- Grounding provenance. A join table rather than the specified uuid[] so the
-- reference is enforced: a question cannot claim to be grounded in a chunk
-- that has been deleted.
create table public.question_source_chunk (
  question_id uuid not null references public.question(id) on delete cascade,
  chunk_id    uuid not null references public.chunk(id)    on delete cascade,
  rank        smallint not null,
  primary key (question_id, chunk_id)
);

create index question_source_chunk_chunk_idx on public.question_source_chunk (chunk_id);

-- ---------------------------------------------------------------------------
-- answer
-- ---------------------------------------------------------------------------

create table public.answer (
  id             uuid primary key default gen_random_uuid(),
  question_id    uuid not null references public.question(id) on delete cascade,
  user_id        uuid not null references public.profile(id)  on delete cascade,

  -- Practice mode allows unlimited attempts. Without an attempt number a
  -- second attempt either overwrites the first or is indistinguishable from
  -- it, and mastery updates double-count (audit DB-09).
  attempt_number smallint not null default 1,

  text           text not null,
  input_mode     public.input_mode not null default 'typed',

  -- Source data for "time spent" in the analytics dashboard, which the
  -- specified schema had no way to compute (audit DB-06).
  duration_ms    integer,

  audio_path     text,

  -- A double-submit on a dropped mobile connection currently creates two
  -- evaluations and two charges. This makes submission idempotent.
  idempotency_key text,

  created_at     timestamptz not null default now(),

  constraint answer_attempt_positive check (attempt_number >= 1),
  constraint answer_duration_sane    check (duration_ms is null or duration_ms between 0 and 7200000),
  constraint answer_voice_has_transcript check (
    input_mode <> 'voice' or length(btrim(text)) > 0
  )
);

create unique index answer_unique_attempt on public.answer (question_id, attempt_number);
create unique index answer_unique_idempotency
  on public.answer (user_id, idempotency_key)
  where idempotency_key is not null;
create index answer_user_idx on public.answer (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- evaluation — immutable
-- ---------------------------------------------------------------------------

create table public.evaluation (
  id                   uuid primary key default gen_random_uuid(),
  answer_id            uuid not null unique references public.answer(id) on delete cascade,
  user_id              uuid not null references public.profile(id) on delete cascade,

  -- The seven rubric dimensions. All seven are stored for research value even
  -- though not all are displayed: the audit expects Concept Accuracy,
  -- Completeness, Depth and Examples Used to correlate strongly, and a hero
  -- visual that never varies is decoration (audit AI-04). Which dimensions
  -- reach the UI is decided from measured inter-dimension correlation on the
  -- gold set, not guessed here.
  concept_accuracy     numeric(5,2) not null,
  completeness         numeric(5,2) not null,
  technical_vocabulary numeric(5,2) not null,
  logical_flow         numeric(5,2) not null,
  depth                numeric(5,2) not null,
  examples_used        numeric(5,2) not null,

  -- Nullable, and excluded from the composite while answers are typed.
  -- Confidence is prosodic; scoring it from text measures hedging vocabulary
  -- and penalises the appropriately cautious. The product's own second
  -- persona is "anxious about oral exams specifically" (audit AI-02).
  confidence           numeric(5,2),

  composite_score      numeric(5,2) not null,

  feedback             text not null,

  -- Provenance. Every number above is reproducible from these.
  model                text not null,
  prompt_version       text not null,
  rubric_version       text not null,
  input_tokens         integer,
  output_tokens        integer,
  cost_usd             numeric(10,6),
  latency_ms           integer,

  created_at           timestamptz not null default now(),

  constraint evaluation_scores_in_range check (
    concept_accuracy     between 0 and 100 and
    completeness         between 0 and 100 and
    technical_vocabulary between 0 and 100 and
    logical_flow         between 0 and 100 and
    depth                between 0 and 100 and
    examples_used        between 0 and 100 and
    composite_score      between 0 and 100 and
    (confidence is null or confidence between 0 and 100)
  )
);

create index evaluation_user_idx on public.evaluation (user_id, created_at desc);

-- An assessment record that can be silently edited is not an assessment
-- record. Enforced by trigger rather than RLS because service_role bypasses
-- RLS, and the backend runs as service_role.
create trigger evaluation_append_only
  before update or delete on public.evaluation
  for each row execute function app.reject_mutation();

-- ---------------------------------------------------------------------------
-- evaluation_gap + evaluation_citation
--
-- FR-4.3 requires a document and page for every concept marked missing.
-- Proposal §15 calls this the product's major innovation. If the model emits
-- {document, page} as free text it will invent plausible page numbers, and a
-- fabricated citation is worse than none: it converts the trust mechanism
-- into the biggest liability, and any student who turns to page 42 catches it.
--
-- So the model may only cite chunk IDs from the retrieved set, and the server
-- resolves them to document + page. A hallucinated citation fails a foreign
-- key rather than reaching a student.
-- ---------------------------------------------------------------------------

create table public.evaluation_gap (
  id            uuid primary key default gen_random_uuid(),
  evaluation_id uuid not null references public.evaluation(id) on delete cascade,
  user_id       uuid not null references public.profile(id) on delete cascade,

  -- Nullable: the evaluator may surface a gap that concept extraction did not
  -- name. Better to record it unmapped than to discard it.
  concept_id    uuid references public.concept(id) on delete set null,

  label         text not null,
  detail        text,
  severity      public.gap_severity not null default 'medium',
  created_at    timestamptz not null default now(),

  constraint evaluation_gap_label_not_blank check (length(btrim(label)) > 0)
);

create index evaluation_gap_evaluation_idx on public.evaluation_gap (evaluation_id);
create index evaluation_gap_concept_idx    on public.evaluation_gap (concept_id);
create index evaluation_gap_user_idx       on public.evaluation_gap (user_id);

create table public.evaluation_citation (
  id         uuid primary key default gen_random_uuid(),
  gap_id     uuid not null references public.evaluation_gap(id) on delete cascade,
  chunk_id   uuid not null references public.chunk(id) on delete restrict,
  user_id    uuid not null references public.profile(id) on delete cascade,
  created_at timestamptz not null default now()
);

create unique index evaluation_citation_unique on public.evaluation_citation (gap_id, chunk_id);
create index evaluation_citation_chunk_idx on public.evaluation_citation (chunk_id);
create index evaluation_citation_user_idx  on public.evaluation_citation (user_id);

-- ---------------------------------------------------------------------------
-- concept_mastery — current state, including FSRS scheduling
--
-- The spec stored the revision schedule as enum(today, tomorrow, weekend,
-- before_exam): no date, no rollover, no record of when it was scheduled.
-- "Today" is meaningless tomorrow (audit DB-03).
--
-- Replaced with FSRS state per concept. The four planner tabs become views
-- over due_at rather than stored buckets — see the revision_queue view.
-- ---------------------------------------------------------------------------

create table public.concept_mastery (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profile(id) on delete cascade,
  subject_id       uuid not null references public.subject(id) on delete cascade,
  concept_id       uuid not null references public.concept(id) on delete cascade,

  mastery_pct      numeric(5,2) not null default 0,
  gap_severity     public.gap_severity not null default 'critical',

  -- Latent ability on this concept, updated after each answer. Drives
  -- difficulty selection: pick the level where predicted success is near 70%.
  -- The spec called adaptive difficulty a core innovation and specified no
  -- policy, which becomes an `if score < 50 go down` branch that oscillates
  -- (audit AI-05).
  ability          numeric(6,3) not null default 0,

  -- FSRS memory state.
  stability        numeric(10,4),
  difficulty       numeric(6,4),
  due_at           timestamptz,
  last_reviewed_at timestamptz,
  review_count     integer not null default 0,
  lapses           integer not null default 0,

  updated_at       timestamptz not null default now(),

  constraint mastery_pct_range   check (mastery_pct between 0 and 100),
  constraint mastery_counts_sane check (review_count >= 0 and lapses >= 0),
  constraint mastery_fsrs_ranges check (
    (stability  is null or stability  > 0) and
    (difficulty is null or difficulty between 1 and 10)
  )
);

create unique index concept_mastery_unique on public.concept_mastery (user_id, concept_id);
create index concept_mastery_due_idx on public.concept_mastery (user_id, due_at)
  where due_at is not null;
create index concept_mastery_subject_idx on public.concept_mastery (subject_id, gap_severity);

create trigger concept_mastery_touch
  before update on public.concept_mastery
  for each row execute function app.touch_updated_at();

-- ---------------------------------------------------------------------------
-- concept_mastery_event — append-only history
--
-- One table restores four features the spec could not compute: the
-- improvement curve (FR-6.1), the prototype's "34% -> 51%", predictive
-- readiness, and session replay. It is also the dataset for the calibration
-- study in the research framing (audit DB-02).
-- ---------------------------------------------------------------------------

create table public.concept_mastery_event (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profile(id) on delete cascade,
  subject_id       uuid not null references public.subject(id) on delete cascade,
  concept_id       uuid not null references public.concept(id) on delete cascade,

  -- Null when the review was a manual revision rather than a scored answer.
  answer_id        uuid references public.answer(id) on delete set null,
  evaluation_id    uuid references public.evaluation(id) on delete set null,
  session_id       uuid references public.viva_session(id) on delete set null,

  prior_mastery    numeric(5,2) not null,
  new_mastery      numeric(5,2) not null,
  prior_ability    numeric(6,3),
  new_ability      numeric(6,3),
  prior_stability  numeric(10,4),
  new_stability    numeric(10,4),
  prior_difficulty numeric(6,4),
  new_difficulty   numeric(6,4),

  -- FSRS grade: 1 again, 2 hard, 3 good, 4 easy. Derived from the composite
  -- score for scored answers; supplied directly for self-assessed revision.
  rating           smallint,

  occurred_at      timestamptz not null default now(),

  constraint mastery_event_pct_range check (
    prior_mastery between 0 and 100 and new_mastery between 0 and 100
  ),
  constraint mastery_event_rating_range check (rating is null or rating between 1 and 4)
);

create index mastery_event_curve_idx on public.concept_mastery_event (user_id, occurred_at);
create index mastery_event_concept_idx on public.concept_mastery_event (concept_id, occurred_at);
create index mastery_event_subject_idx on public.concept_mastery_event (subject_id, occurred_at);

create trigger mastery_event_append_only
  before update or delete on public.concept_mastery_event
  for each row execute function app.reject_mutation();
