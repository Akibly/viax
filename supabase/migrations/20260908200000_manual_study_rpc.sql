-- Migration to add RPC for manual study sessions (Flashcards, Match, etc)
-- This allows the frontend to submit scores that bypass the AI evaluation pipeline
-- but still update the FSRS schedule and Readiness scores.

create or replace function public.submit_study_results(
  p_subject_id uuid,
  p_results jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id     uuid;
  v_exam        date;
  
  v_item        jsonb;
  v_concept     uuid;
  v_score       numeric;
  v_rating      integer;

  v_prior_mastery   numeric;
  v_prior_ability   numeric;
  v_prior_stability numeric;
  v_prior_difficulty numeric;
  v_reviews  integer;
  v_lapses   integer;
  v_existing boolean;

  v_mastery    numeric;
  v_ability    numeric;
  v_stability  numeric;
  v_difficulty numeric;
  v_interval   numeric;
  v_due        timestamptz;
begin
  v_user_id := app.current_user_id();
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select exam_date into v_exam
    from public.subject
   where id = p_subject_id and user_id = v_user_id;

  if not found then
    raise exception 'Subject not found or access denied';
  end if;

  for v_item in select * from jsonb_array_elements(p_results) loop
    v_concept := (v_item->>'concept_id')::uuid;
    v_score   := (v_item->>'score')::numeric;
    v_rating  := app.rating_from_score(v_score);

    -- Load existing mastery
    select true, cm.mastery_pct, cm.ability, cm.stability, cm.difficulty, cm.review_count, cm.lapses
      into v_existing, v_prior_mastery, v_prior_ability, v_prior_stability, v_prior_difficulty, v_reviews, v_lapses
      from public.concept_mastery cm
     where cm.concept_id = v_concept
       and cm.user_id = v_user_id;

    if not found then
      v_existing := false;
      v_prior_mastery := 0;
      v_prior_ability := 0;
      v_reviews := 0;
      v_lapses := 0;
    end if;

    -- Calculate Mastery (0.65 prior + 0.35 new)
    v_mastery := case
      when v_existing then round(0.65 * v_prior_mastery + 0.35 * v_score, 1)
      else round(v_score, 1)
    end;
    v_mastery := greatest(0, least(100, v_mastery));

    -- Difficulty
    v_difficulty := coalesce(v_prior_difficulty, 5);
    v_difficulty := greatest(1, least(10, v_difficulty + (3 - v_rating) * 0.5));

    -- Stability
    if not v_existing or v_prior_stability is null then
      v_stability := case v_rating
        when 1 then 0.5
        when 2 then 1.2
        when 3 then 2.5
        else 4.0
      end;
    elsif v_rating = 1 then
      v_stability := greatest(0.4, v_prior_stability * 0.45);
      v_lapses := v_lapses + 1;
    else
      v_stability := v_prior_stability * (1 + (v_rating - 1) * 0.9 * (11 - v_difficulty) / 10);
    end if;
    v_stability := least(365, v_stability);

    -- Ability
    v_ability := round(
      coalesce(v_prior_ability, 0) * 0.7 + (v_score / 100.0) * 0.3, 4);

    v_interval := v_stability;
    v_due := now() + (v_interval || ' days')::interval;

    if v_exam is not null then
      if v_due::date > v_exam then
        v_due := least(v_due, (v_exam::timestamptz - interval '1 day'));
        if v_due < now() then
          v_due := now() + interval '4 hours';
        end if;
      end if;
    end if;

    -- Upsert mastery
    insert into public.concept_mastery as cm (
      user_id, subject_id, concept_id, mastery_pct, ability,
      stability, difficulty, due_at, last_reviewed_at, review_count, lapses,
      gap_severity
    )
    values (
      v_user_id, p_subject_id, v_concept, v_mastery, v_ability,
      round(v_stability, 3), round(v_difficulty, 2), v_due, now(),
      1, v_lapses,
      app.severity_for(v_mastery)
    )
    on conflict (user_id, concept_id) do update set
      mastery_pct = excluded.mastery_pct,
      ability = excluded.ability,
      stability = excluded.stability,
      difficulty = excluded.difficulty,
      due_at = excluded.due_at,
      last_reviewed_at = excluded.last_reviewed_at,
      review_count = cm.review_count + 1,
      lapses = excluded.lapses,
      gap_severity = excluded.gap_severity;

    -- Insert event
    insert into public.concept_mastery_event (
      user_id, subject_id, concept_id,
      answer_id, evaluation_id, session_id,
      prior_mastery, new_mastery,
      prior_ability, new_ability,
      prior_stability, new_stability,
      prior_difficulty, new_difficulty,
      rating, occurred_at
    )
    values (
      v_user_id, p_subject_id, v_concept,
      null, null, null,
      coalesce(v_prior_mastery, 0), v_mastery,
      v_prior_ability, v_ability,
      v_prior_stability, round(v_stability, 3),
      v_prior_difficulty, round(v_difficulty, 2),
      v_rating, now()
    );
  end loop;
end;
$$;

revoke all on function public.submit_study_results(uuid, jsonb) from public, anon;
grant execute on function public.submit_study_results(uuid, jsonb) to authenticated;
