-- Mastery that actually decays.
--
-- The readiness screen tells a student, in words: "Mastery, decayed by time —
-- older readings count for less. Memory fades, so a score from three weeks
-- ago should not carry the same weight as one from this morning."
--
-- Nothing decayed anything. `mastery_pct` changed only when an answer was
-- submitted, so a concept last examined in March read identically today. That
-- is not a missing feature — it is the product making a false statement about
-- a student's own assessment, on the screen whose entire purpose is to
-- explain how the number is computed.
--
-- Decay is computed at read time rather than written by a nightly job. A job
-- would need scheduling this project does not have, would make the stored
-- value wrong between runs, and would destroy the raw observation. Deriving
-- it keeps `mastery_pct` meaning "what they scored" and lets
-- `effective_mastery` mean "what they can be expected to recall now" — two
-- different questions that were previously answered by one number.
--
-- The curve is the standard exponential forgetting model, R = e^(-t/S), with
-- stability taken from the scheduler that already tracks it. A concept with a
-- 30-day stability barely moves in a week; one with a 0.5-day stability
-- collapses overnight, which is exactly what a lapse should mean.

create or replace function app.decayed_mastery(
  p_mastery      numeric,
  p_stability    numeric,
  p_last_reviewed timestamptz
)
returns numeric
language sql
immutable
as $$
  select case
    -- Never examined, or examined with no stability recorded: nothing to
    -- decay, and inventing a decline would be as wrong as inventing a score.
    when p_mastery is null or p_last_reviewed is null or p_stability is null
      then p_mastery
    else greatest(
      0,
      round(
        p_mastery * exp(
          -greatest(
            extract(epoch from (now() - p_last_reviewed)) / 86400.0,
            0
          ) / greatest(p_stability, 0.25)
        )::numeric,
        1
      )
    )
  end;
$$;

comment on function app.decayed_mastery is
  'Exponential forgetting: R = mastery * e^(-days / stability). Stability comes from the review history, so a well-known concept decays slowly and a lapsed one falls away fast.';

-- Prove the curve behaves before anything depends on it.
do $$
declare
  v_fresh numeric;
  v_week  numeric;
  v_stale numeric;
begin
  -- Just reviewed: essentially unchanged.
  v_fresh := app.decayed_mastery(80, 10, now() - interval '1 hour');
  if v_fresh < 79 then
    raise exception 'a concept reviewed an hour ago should not have decayed: %', v_fresh;
  end if;

  -- One stability-period later: down by roughly 1/e.
  v_week := app.decayed_mastery(80, 7, now() - interval '7 days');
  if v_week > 32 or v_week < 26 then
    raise exception 'one stability period should leave about 37%% of 80, got %', v_week;
  end if;

  -- Long past a short stability: near zero.
  v_stale := app.decayed_mastery(80, 1, now() - interval '30 days');
  if v_stale > 1 then
    raise exception 'a 1-day-stability concept unseen for 30 days should be ~0, got %', v_stale;
  end if;

  -- Never examined stays null rather than becoming a zero.
  if app.decayed_mastery(null, 10, now()) is not null then
    raise exception 'an unexamined concept must not decay into a score';
  end if;
end $$;

-- Adding OUT columns changes the row type, which Postgres will not do in
-- place. Dropped and recreated rather than versioned under a new name: the
-- old shape has no callers left once this migration lands.
drop function if exists public.subject_readiness(uuid);

-- Readiness now reflects what a student can recall today, not what they once
-- scored. Both figures are returned so the explain screen can show the drop
-- rather than silently applying it.
create or replace function public.subject_readiness(p_subject_id uuid)
returns table (
  total_concepts    integer,
  examined_concepts integer,
  coverage_pct      numeric,
  mean_mastery      numeric,
  mean_effective    numeric,
  decay_loss        numeric
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.subject s
     where s.id = p_subject_id
       and s.user_id = app.current_user_id()
       and s.deleted_at is null
  ) then
    raise exception 'subject not found' using errcode = '42501';
  end if;

  return query
    select
      count(*)::integer,
      count(*) filter (where cm.mastery_pct is not null)::integer,
      round(100.0 * count(*) filter (where cm.mastery_pct is not null)
            / greatest(count(*), 1), 1),
      round(coalesce(avg(cm.mastery_pct), 0), 1),
      round(coalesce(avg(app.decayed_mastery(
        cm.mastery_pct, cm.stability, cm.last_reviewed_at)), 0), 1),
      -- What forgetting has cost since those answers were given. This is the
      -- number the explain screen was describing all along.
      round(
        coalesce(avg(cm.mastery_pct), 0)
        - coalesce(avg(app.decayed_mastery(
            cm.mastery_pct, cm.stability, cm.last_reviewed_at)), 0),
        1
      )
      from public.concept c
      left join public.concept_mastery cm on cm.concept_id = c.id
     where c.subject_id = p_subject_id;
end;
$$;

revoke all on function public.subject_readiness(uuid) from public, anon;
grant execute on function public.subject_readiness(uuid) to authenticated;

-- The concept list should rank by what a student can recall now, so a topic
-- that has quietly faded rises to the top instead of sitting on a stale
-- score from a month ago.
create or replace view public.concept_standing as
  select
    c.id                as concept_id,
    c.subject_id,
    c.user_id,
    c.canonical_name,
    c.importance,
    cm.mastery_pct,
    app.decayed_mastery(cm.mastery_pct, cm.stability, cm.last_reviewed_at)
                        as effective_mastery,
    cm.stability,
    cm.review_count,
    cm.lapses,
    cm.due_at,
    cm.last_reviewed_at
  from public.concept c
  left join public.concept_mastery cm on cm.concept_id = c.id;

comment on view public.concept_standing is
  'Concepts with both the raw mastery and what it decays to today. The view is security_invoker, so the caller''s RLS on concept and concept_mastery still applies.';

alter view public.concept_standing set (security_invoker = true);
grant select on public.concept_standing to authenticated;
