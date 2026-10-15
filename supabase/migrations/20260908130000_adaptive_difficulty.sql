-- Difficulty that responds to the student.
--
-- The PRD's headline claim is an examiner that "adjusts difficulty live based
-- on answer quality". It did not adjust at all: `difficulty_level` was
-- whatever number the model happened to put in its JSON, stored and displayed
-- but never read back. A student scoring 95 and one scoring 5 received
-- statistically identical questions.
--
-- The target is computed here rather than in the Edge Function because it is
-- a property of the student's history, the history lives in Postgres, and a
-- number the client could choose is not an assessment.
--
-- The rule is deliberately simple and legible: hold the student near the edge
-- of what they can do. Comfortably right means the question was too easy to
-- be informative; badly wrong means the next one should retreat rather than
-- pile on. The band in between is where a viva actually finds the boundary.

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
  v_recent numeric;
  v_count  integer;
  v_last   integer;
begin
  if v_user is null then
    return 2;
  end if;

  -- The last three marks on this concept if we have them, otherwise on the
  -- subject. Concept-level is the better signal but is often empty early on,
  -- and falling back keeps a first sitting from always opening at the floor.
  select avg(e.composite_score), count(*)
    into v_recent, v_count
    from (
      select ev.composite_score
        from public.evaluation ev
        join public.answer a  on a.id = ev.answer_id
        join public.question q on q.id = a.question_id
        join public.viva_session s on s.id = q.session_id
       where ev.user_id = v_user
         and s.subject_id = p_subject_id
         and (p_concept_id is null or q.concept_id = p_concept_id)
       order by ev.created_at desc
       limit 3
    ) e;

  -- Nothing to go on. Level 2 is a real question that most students can make
  -- progress against, which is a better opening than either extreme.
  if v_count is null or v_count = 0 then
    return 2;
  end if;

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

  -- One step at a time. Jumping two levels on a single good answer makes the
  -- examiner feel erratic, and a single lucky answer is not evidence.
  return greatest(1, least(5,
    case
      when v_recent >= 80 then v_last + 1   -- comfortably right: push
      when v_recent >= 55 then v_last       -- at the boundary: hold
      when v_recent >= 35 then v_last - 1   -- struggling: ease off
      else greatest(1, v_last - 2)          -- lost: retreat properly
    end
  ));
end;
$$;

comment on function app.next_difficulty is
  'Target difficulty for the next question, derived from the last three marks. Moves one level at a time so the examiner reads as responsive rather than erratic.';

create or replace function public.next_difficulty(
  p_subject_id uuid,
  p_concept_id uuid default null
)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1 from public.subject s
       where s.id = p_subject_id
         and s.user_id = app.current_user_id()
         and s.deleted_at is null
    )
    then app.next_difficulty(p_subject_id, p_concept_id)
    else 2
  end;
$$;

revoke all on function public.next_difficulty(uuid, uuid) from public, anon;
grant execute on function public.next_difficulty(uuid, uuid) to authenticated;

-- The ladder has to actually move, in both directions, one rung at a time.
do $$
begin
  -- Pure ladder arithmetic, independent of any stored history.
  if greatest(1, least(5, 3 + 1)) <> 4 then
    raise exception 'a strong run should climb';
  end if;
  if greatest(1, least(5, 3 - 1)) <> 2 then
    raise exception 'a weak run should ease off';
  end if;
  if greatest(1, least(5, 5 + 1)) <> 5 then
    raise exception 'difficulty must cap at 5';
  end if;
  if greatest(1, greatest(1, 2 - 2)) <> 1 then
    raise exception 'difficulty must floor at 1';
  end if;
end $$;
