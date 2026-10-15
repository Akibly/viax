-- Letting the assessed contest the assessment.
--
-- Nowhere in the original schema could a student say "that mark is wrong".
-- For a product whose whole function is to judge people that is two problems
-- at once: a fairness gap, and a wasted asset.
--
-- The asset matters as much as the fairness. Every challenge is a labelled
-- example — a case where the model and the person disagree — and the rate of
-- them is the cheapest calibration signal this product will ever get. A
-- rubric weight that is wrong shows up here long before it shows up in a
-- gold-set evaluation somebody has to fund.
--
-- The reason is a constrained set rather than free text alone, because a
-- complaint you can count is evidence and a paragraph is an anecdote. The
-- free text sits alongside it, not instead of it.

create type public.dispute_reason as enum (
  'marked_wrong',    -- flagged something the student is confident is right
  'missed_point',    -- the point was made and the mark says otherwise
  'outside_notes',   -- asked about material the notes do not cover
  'too_harsh',       -- reasonable answer, unreasonable number
  'bad_citation'     -- the cited passage does not support the gap
);

create table public.evaluation_dispute (
  id            uuid primary key default gen_random_uuid(),
  evaluation_id uuid not null references public.evaluation(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  reason        public.dispute_reason not null,
  detail        text,
  -- Recorded at the time of the challenge: the mark is append-only, but the
  -- weights and prompt behind it change, and a dispute is only interpretable
  -- against the version that produced the score.
  scored        numeric(5,2) not null,
  rubric_version text not null default 'v1',
  status        text not null default 'open'
                  check (status in ('open', 'reviewed', 'upheld', 'rejected')),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),

  constraint dispute_detail_length check (detail is null or length(detail) <= 2000),
  -- One challenge per evaluation: a second is a duplicate, not new evidence,
  -- and counting duplicates would inflate the disagreement rate.
  constraint dispute_one_per_evaluation unique (evaluation_id)
);

comment on table public.evaluation_dispute is
  'Student challenges to a mark. Feeds the calibration set; the disagreement rate is a product health metric.';

create index evaluation_dispute_user on public.evaluation_dispute (user_id, created_at desc);
create index evaluation_dispute_open on public.evaluation_dispute (status) where status = 'open';

alter table public.evaluation_dispute enable row level security;

create policy evaluation_dispute_select_own on public.evaluation_dispute
  for select to authenticated
  using (user_id = (select app.current_user_id()));

-- The evaluation must belong to the person challenging it. Without this a
-- student could file complaints against marks they never received, which
-- would poison exactly the signal this table exists to produce.
create policy evaluation_dispute_insert_own on public.evaluation_dispute
  for insert to authenticated
  with check (
    user_id = (select app.current_user_id())
    and exists (
      select 1 from public.evaluation e
       where e.id = evaluation_id
         and e.user_id = (select app.current_user_id())
    )
  );

-- No update or delete for students: a withdrawn complaint is still a
-- disagreement, and letting it vanish would bias the metric toward agreement.
grant select, insert on public.evaluation_dispute to authenticated;
