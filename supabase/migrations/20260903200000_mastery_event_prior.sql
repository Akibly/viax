-- concept_mastery_event.prior_mastery is NOT NULL.
--
-- The previous fix handled the NOT NULL columns on concept_mastery but not
-- the ones on its event log, so a concept's first review still failed — the
-- same path, one table further along. Both were found the same way: by
-- running a real answer through, not by reading the schema.
--
-- prior_mastery becomes 0 on a first review, matching the column default that
-- an absent concept_mastery row already implies. The nullable columns
-- (ability, stability, difficulty) stay null, because those genuinely had no
-- prior value and inventing one would corrupt the audit trail.

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

  v_prior_mastery    numeric;
  v_prior_ability    numeric;
  v_prior_stability  numeric;
  v_prior_difficulty numeric;
  v_reviews  integer;
  v_lapses   integer;
  v_existing boolean;

  v_mastery    numeric;
  v_ability    numeric;
  v_stability  numeric;
  v_difficulty numeric;
  v_due        timestamptz;
begin
  select q.concept_id, s.subject_id, q.session_id, subj.exam_date
    into v_concept, v_subject, v_session, v_exam
    from public.answer a
    join public.question q on q.id = a.question_id
    join public.viva_session s on s.id = q.session_id
    join public.subject subj on subj.id = s.subject_id
   where a.id = new.answer_id;

  if v_concept is null then
    return null;
  end if;

  select cm.mastery_pct, cm.ability, cm.stability, cm.difficulty,
         cm.review_count, cm.lapses
    into v_prior_mastery, v_prior_ability, v_prior_stability,
         v_prior_difficulty, v_reviews, v_lapses
    from public.concept_mastery cm
   where cm.concept_id = v_concept
     and cm.user_id = new.user_id;

  -- FOUND is the only reliable signal here; the variables above are all NULL
  -- when the select matched nothing, initialiser or not.
  v_existing := found;
  if not v_existing then
    v_prior_mastery := null;
    v_prior_ability := null;
    v_reviews := 0;
    v_lapses := 0;
  end if;
  v_lapses := coalesce(v_lapses, 0);
  v_reviews := coalesce(v_reviews, 0);

  v_rating := app.rating_from_score(new.composite_score);

  -- Exponentially weighted, so one bad morning does not erase a month of work
  -- and one lucky answer does not declare mastery.
  v_mastery := case
    when v_existing then round(0.65 * coalesce(v_prior_mastery, 0) + 0.35 * new.composite_score, 1)
    else round(new.composite_score, 1)
  end;
  v_mastery := greatest(0, least(100, v_mastery));

  v_difficulty := coalesce(v_prior_difficulty, 5);
  v_difficulty := greatest(1, least(10, v_difficulty + (3 - v_rating) * 0.5));

  if not v_existing or v_prior_stability is null then
    v_stability := case v_rating
      when 1 then 0.5
      when 2 then 1.2
      when 3 then 2.5
      else 4.0
    end;
  elsif v_rating = 1 then
    -- A lapse collapses stability rather than decaying it gently; that is why
    -- lapses are counted separately from reviews.
    v_stability := greatest(0.4, v_prior_stability * 0.45);
    v_lapses := v_lapses + 1;
  else
    v_stability := v_prior_stability *
      (1 + (v_rating - 1) * 0.9 * (11 - v_difficulty) / 10);
  end if;
  v_stability := least(365, greatest(0.25, v_stability));

  v_ability := round(
    coalesce(v_prior_ability, 0) * 0.7 + (new.composite_score / 100.0) * 0.3, 4);

  v_due := now() + (v_stability || ' days')::interval;

  -- Nothing may be scheduled past the exam, and a weak concept is pulled well
  -- inside it. Generic spacing cannot do this; an exam date is what makes the
  -- schedule specific to one student.
  if v_exam is not null and v_due::date > v_exam then
    v_due := greatest(now() + interval '4 hours',
                      v_exam::timestamptz - interval '1 day');
  end if;

  insert into public.concept_mastery as cm (
    user_id, subject_id, concept_id, mastery_pct, ability,
    stability, difficulty, due_at, last_reviewed_at, review_count, lapses,
    gap_severity, updated_at
  )
  values (
    new.user_id, v_subject, v_concept, v_mastery, v_ability,
    round(v_stability, 3), round(v_difficulty, 2), v_due, now(),
    1, v_lapses, app.severity_for(v_mastery), now()
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

  insert into public.concept_mastery_event (
    user_id, subject_id, concept_id, answer_id, evaluation_id, session_id,
    prior_mastery, new_mastery, prior_ability, new_ability,
    prior_stability, new_stability, prior_difficulty, new_difficulty,
    rating, occurred_at
  )
  values (
    new.user_id, v_subject, v_concept, new.answer_id, new.id, v_session,
    -- prior_mastery is NOT NULL, and a concept with no row sits at the
    -- column's own default of 0 — so that is the honest prior, not a
    -- fabricated one. The ability/stability/difficulty columns are
    -- nullable precisely so a first review can say "there was nothing
    -- here before", and they keep saying it.
    coalesce(v_prior_mastery, 0), v_mastery, v_prior_ability, v_ability,
    v_prior_stability, round(v_stability, 3),
    v_prior_difficulty, round(v_difficulty, 2),
    v_rating, now()
  );

  return null;
end;
$$;
