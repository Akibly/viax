-- Recalibrating the difficulty ladder against how the examiner actually marks.
--
-- The first version held a student at level 2 through scores of 79, 35, 80
-- and 70. The rule was working exactly as written; the thresholds were wrong.
--
-- Two mistakes, both from calibrating against imagined marks rather than
-- observed ones:
--
--   * The push threshold was 80. Measured across live runs, a genuinely
--     strong answer scores 70-80 and a weak one scores 0-10 — this examiner
--     marks harshly, so 79 was being treated as mediocre when it is close to
--     the best the rubric gives out.
--
--   * A flat mean of the last three responds too slowly. One bad answer in
--     the middle of a good run dragged the average into the hold band and
--     kept it there, so the ladder never moved in either direction.
--
-- The fix weights recency: the most recent answer carries half the signal.
-- A student who has just improved should feel that on the next question, not
-- three questions later.

create or replace function app.next_difficulty(
  p_subject_id uuid,
  p_concept_id uuid default null
)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_scores numeric[];
  v_signal numeric;
  v_last   integer;
begin
  if v_user is null then
    return 2;
  end if;

  select array_agg(score order by rn)
    into v_scores
    from (
      select ev.composite_score as score,
             row_number() over (order by ev.created_at desc) as rn
        from public.evaluation ev
        join public.answer a   on a.id = ev.answer_id
        join public.question q on q.id = a.question_id
        join public.viva_session s on s.id = q.session_id
       where ev.user_id = v_user
         and s.subject_id = p_subject_id
         and (p_concept_id is null or q.concept_id = p_concept_id)
       order by ev.created_at desc
       limit 3
    ) recent;

  if v_scores is null or array_length(v_scores, 1) = 0 then
    return 2;
  end if;

  -- Recency-weighted: 50 / 30 / 20. Normalised by the weights actually
  -- present, so a student with one answer is judged on that answer rather
  -- than on it diluted by two absent ones.
  v_signal := (
    coalesce(v_scores[1], 0) * 0.5
    + coalesce(v_scores[2], 0) * 0.3
    + coalesce(v_scores[3], 0) * 0.2
  ) / (
    0.5
    + case when v_scores[2] is not null then 0.3 else 0 end
    + case when v_scores[3] is not null then 0.2 else 0 end
  );

  select q.difficulty_level
    into v_last
    from public.question q
    join public.viva_session s on s.id = q.session_id
   where q.user_id = v_user
     and s.subject_id = p_subject_id
     and (p_concept_id is null or q.concept_id = p_concept_id)
   order by q.created_at desc
   limit 1;

  v_last := coalesce(v_last, 2);

  -- Bands set from observed marking, not from what a human examiner would
  -- give. Still one step at a time: a single lucky answer is not evidence.
  return greatest(1, least(5,
    case
      when v_signal >= 70 then v_last + 1   -- as good as this rubric gets
      when v_signal >= 45 then v_last       -- at the boundary: hold
      when v_signal >= 25 then v_last - 1   -- struggling: ease off
      else greatest(1, v_last - 2)          -- lost: retreat properly
    end
  ));
end;
$$;

comment on function app.next_difficulty is
  'Target difficulty from a recency-weighted read of the last three marks (50/30/20). Bands calibrated against observed scoring, where a strong answer lands at 70-80 rather than 90+.';

-- The weighting must actually favour the latest answer, or the ladder is
-- still a slow mean under a new name.
do $$
declare
  v_recovering numeric;
  v_declining  numeric;
begin
  -- Two bad answers then a good one should read as recovering, not as weak.
  v_recovering := (80 * 0.5 + 30 * 0.3 + 20 * 0.2) / 1.0;
  if v_recovering < 45 then
    raise exception 'a recovering student should not still read as struggling: %', v_recovering;
  end if;

  -- Two good answers then a bad one should read as slipping.
  v_declining := (20 * 0.5 + 80 * 0.3 + 80 * 0.2) / 1.0;
  if v_declining >= 70 then
    raise exception 'a student who just failed should not still be pushed up: %', v_declining;
  end if;
end $$;
