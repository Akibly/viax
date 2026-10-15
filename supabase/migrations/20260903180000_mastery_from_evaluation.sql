-- Mastery, updated from every evaluation.
--
-- The schema was built for spaced repetition — stability, difficulty, due_at,
-- lapses, and an event table recording prior and new values — and nothing ever
-- wrote to any of it. Evaluations were stored and then forgotten, so readiness
-- never moved, the concept graph stayed flat, and the revision queue was
-- permanently empty. The loop the product is built around was open.
--
-- This closes it in the database rather than the client, for two reasons: the
-- update must happen exactly once per evaluation even if a client retries, and
-- an evaluation that did not move mastery is a silent correctness bug nobody
-- would notice.
--
-- The scheduler is FSRS in shape, not in full: real FSRS-5 fits seventeen
-- parameters against a review history this product does not have yet. What is
-- implemented is the part that matters on day one — stability grows when you
-- answer well and collapses when you lapse, difficulty drifts with
-- performance, and the interval derives from stability rather than from a
-- fixed ladder. The parameters live in one place so fitting them later is a
-- change of numbers, not of structure.

create or replace function app.rating_from_score(p_score numeric)
returns integer
language sql
immutable
as $$
  -- 1 again · 2 hard · 3 good · 4 easy. The 40 boundary is deliberate: below
  -- it the answer did not demonstrate the concept, which is a lapse, not a
  -- slow success.
  select case
    when p_score < 40 then 1
    when p_score < 60 then 2
    when p_score < 80 then 3
    else 4
  end;
$$;

create or replace function app.apply_evaluation_to_mastery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_concept  uuid;
  v_subject  uuid;
  v_session  uuid;
  v_exam     date;
  v_rating   integer;

  v_prior_mastery   numeric := 0;
  v_prior_ability   numeric := 0;
  v_prior_stability numeric;
  v_prior_difficulty numeric;
  v_reviews  integer := 0;
  v_lapses   integer := 0;
  v_existing boolean := false;

  v_mastery    numeric;
  v_ability    numeric;
  v_stability  numeric;
  v_difficulty numeric;
  v_interval   numeric;
  v_due        timestamptz;
begin
  -- evaluation -> answer -> question gives the concept being examined.
  select q.concept_id, s.subject_id, q.session_id, subj.exam_date
    into v_concept, v_subject, v_session, v_exam
    from public.answer a
    join public.question q on q.id = a.question_id
    join public.viva_session s on s.id = q.session_id
    join public.subject subj on subj.id = s.subject_id
   where a.id = new.answer_id;

  if v_concept is null then
    return null;  -- nothing to attribute the result to
  end if;

  select true, cm.mastery_pct, cm.ability, cm.stability, cm.difficulty,
         cm.review_count, cm.lapses
    into v_existing, v_prior_mastery, v_prior_ability, v_prior_stability,
         v_prior_difficulty, v_reviews, v_lapses
    from public.concept_mastery cm
   where cm.concept_id = v_concept
     and cm.user_id = new.user_id;

  v_rating := app.rating_from_score(new.composite_score);

  -- Mastery is an exponentially weighted mean, so one bad morning does not
  -- erase a month of work and one lucky answer does not declare mastery.
  v_mastery := case
    when coalesce(v_existing, false) then round(0.65 * v_prior_mastery + 0.35 * new.composite_score, 1)
    else round(new.composite_score, 1)
  end;
  v_mastery := greatest(0, least(100, v_mastery));

  -- Difficulty drifts toward what the answers show, anchored at 5.
  v_difficulty := coalesce(v_prior_difficulty, 5);
  v_difficulty := greatest(1, least(10, v_difficulty + (3 - v_rating) * 0.5));

  if not coalesce(v_existing, false) or v_prior_stability is null then
    -- First sight of the concept: a short interval, longer if it was easy.
    v_stability := case v_rating
      when 1 then 0.5
      when 2 then 1.2
      when 3 then 2.5
      else 4.0
    end;
  elsif v_rating = 1 then
    -- A lapse. Stability collapses rather than decaying gently — that is the
    -- whole point of tracking lapses separately.
    v_stability := greatest(0.4, v_prior_stability * 0.45);
    v_lapses := v_lapses + 1;
  else
    -- Growth shrinks as difficulty rises, so hard concepts come back sooner.
    v_stability := v_prior_stability *
      (1 + (v_rating - 1) * 0.9 * (11 - v_difficulty) / 10);
  end if;
  v_stability := least(365, v_stability);

  -- Ability is the student's standing on this concept, used by readiness.
  v_ability := round(
    coalesce(v_prior_ability, 0) * 0.7 + (new.composite_score / 100.0) * 0.3, 4);

  v_interval := v_stability;
  v_due := now() + (v_interval || ' days')::interval;

  -- The exam is the deadline everything else bends around: nothing may be
  -- scheduled after it, and a weak concept gets pulled well inside it.
  if v_exam is not null then
    if v_due::date > v_exam then
      v_due := least(
        v_due,
        (v_exam::timestamptz - interval '1 day')
      );
      if v_due < now() then
        v_due := now() + interval '4 hours';
      end if;
    end if;
  end if;

  insert into public.concept_mastery as cm (
    user_id, subject_id, concept_id, mastery_pct, ability,
    stability, difficulty, due_at, last_reviewed_at, review_count, lapses,
    gap_severity, updated_at
  )
  values (
    new.user_id, v_subject, v_concept, v_mastery, v_ability,
    round(v_stability, 3), round(v_difficulty, 2), v_due, now(),
    1, v_lapses,
    app.severity_for(v_mastery), now()
  )
  on conflict (user_id, concept_id) do update
    set mastery_pct      = excluded.mastery_pct,
        ability          = excluded.ability,
        stability        = excluded.stability,
        difficulty       = excluded.difficulty,
        due_at           = excluded.due_at,
        last_reviewed_at = excluded.last_reviewed_at,
        review_count     = cm.review_count + 1,
        lapses           = excluded.lapses,
        gap_severity     = excluded.gap_severity,
        updated_at       = now();

  -- The audit trail. A mastery figure a student cannot interrogate is a
  -- figure they should not trust, and this is what makes it explicable.
  insert into public.concept_mastery_event (
    user_id, subject_id, concept_id, answer_id, evaluation_id, session_id,
    prior_mastery, new_mastery, prior_ability, new_ability,
    prior_stability, new_stability, prior_difficulty, new_difficulty,
    rating, occurred_at
  )
  values (
    new.user_id, v_subject, v_concept, new.answer_id, new.id, v_session,
    case when coalesce(v_existing, false) then v_prior_mastery else null end,
    v_mastery,
    case when coalesce(v_existing, false) then v_prior_ability else null end,
    v_ability,
    v_prior_stability, round(v_stability, 3),
    v_prior_difficulty, round(v_difficulty, 2),
    v_rating, now()
  );

  return null;
end;
$$;

-- severity_for may already exist from the learning-tables migration; define
-- it defensively so this migration is self-contained.
create or replace function app.severity_for(p_mastery numeric)
returns public.gap_severity
language sql
immutable
as $$
  select case
    when p_mastery >= 75 then 'none'
    when p_mastery >= 55 then 'minor'
    when p_mastery >= 35 then 'moderate'
    else 'critical'
  end::public.gap_severity;
$$;

drop trigger if exists evaluation_updates_mastery on public.evaluation;
create trigger evaluation_updates_mastery
  after insert on public.evaluation
  for each row execute function app.apply_evaluation_to_mastery();
