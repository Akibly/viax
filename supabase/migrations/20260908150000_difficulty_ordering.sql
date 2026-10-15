-- Break the tie when picking "the last question asked".
--
-- next_difficulty read the previous level with `order by created_at desc
-- limit 1`. Inside a single transaction `now()` is frozen, so every question
-- created together shares a timestamp and the "latest" one is chosen
-- arbitrarily — the ladder then climbed once and stuck, because it kept
-- reading a stale level to step from.
--
-- Production usually escapes this because questions arrive in separate
-- requests, but two in the same millisecond is not impossible and the failure
-- would be silent: an examiner that quietly stops adapting looks identical to
-- one that has settled on the right level.
--
-- `ordinal` is monotonic within a session and is the field that actually
-- means "which question came next", so it breaks the tie correctly.

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
             row_number() over (
               order by ev.created_at desc, q.ordinal desc
             ) as rn
        from public.evaluation ev
        join public.answer a   on a.id = ev.answer_id
        join public.question q on q.id = a.question_id
        join public.viva_session s on s.id = q.session_id
       where ev.user_id = v_user
         and s.subject_id = p_subject_id
         and (p_concept_id is null or q.concept_id = p_concept_id)
       order by ev.created_at desc, q.ordinal desc
       limit 3
    ) recent;

  if v_scores is null or array_length(v_scores, 1) = 0 then
    return 2;
  end if;

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
   order by q.created_at desc, q.ordinal desc
   limit 1;

  v_last := coalesce(v_last, 2);

  return greatest(1, least(5,
    case
      when v_signal >= 70 then v_last + 1
      when v_signal >= 45 then v_last
      when v_signal >= 25 then v_last - 1
      else greatest(1, v_last - 2)
    end
  ));
end;
$$;

comment on function app.next_difficulty is
  'Target difficulty from a recency-weighted read of the last three marks (50/30/20), stepping one level from the previous question. Ordered by created_at then ordinal so simultaneous rows cannot make the step ambiguous.';
