-- Follow-up questions: the thing that makes a viva a viva.
--
-- Until now every question was standalone. The examiner asked, marked, and
-- moved to an unrelated concept. That is a quiz with prose feedback — the one
-- behaviour that defines an oral examination, the examiner pressing on a weak
-- answer, was explicitly forbidden in the prompt ("No follow-up").
--
-- A real viva finds the boundary of understanding by probing. A student who
-- gives a half-answer learns nothing from being asked about something else;
-- they learn from being asked "you said X — what about Y?" and discovering
-- where their model breaks.
--
-- The link is stored rather than inferred. Two questions on the same concept
-- in the same session are not necessarily a probe and its parent, and a
-- transcript that cannot distinguish them cannot show the thread.

alter table public.question
  add column parent_question_id uuid references public.question(id) on delete set null;

comment on column public.question.parent_question_id is
  'The question this one probes. NULL for an opening question. Set when the examiner presses on a specific gap rather than moving on.';

create index question_parent on public.question (parent_question_id)
  where parent_question_id is not null;

-- A probe must belong to the same sitting and the same concept as its parent,
-- and must not point at itself. Enforced here because a follow-up that has
-- drifted to another concept is not a follow-up, and the transcript would be
-- lying about the thread.
create or replace function app.enforce_followup_lineage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent public.question%rowtype;
begin
  if new.parent_question_id is null then
    return new;
  end if;

  if new.parent_question_id = new.id then
    raise exception 'a question cannot follow up on itself'
      using errcode = 'integrity_constraint_violation';
  end if;

  select * into v_parent
    from public.question
   where id = new.parent_question_id;

  if not found then
    raise exception 'parent question does not exist'
      using errcode = 'foreign_key_violation';
  end if;

  if v_parent.user_id <> new.user_id then
    raise exception 'cannot follow up on another student''s question'
      using errcode = '42501';
  end if;

  if v_parent.session_id <> new.session_id then
    raise exception 'a follow-up must stay in the same sitting'
      using errcode = 'integrity_constraint_violation';
  end if;

  if v_parent.concept_id <> new.concept_id then
    raise exception 'a follow-up must stay on the same concept'
      using errcode = 'integrity_constraint_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists question_followup_lineage on public.question;
create trigger question_followup_lineage
  before insert on public.question
  for each row execute function app.enforce_followup_lineage();

/*
 * Should the examiner press, or move on?
 *
 * Probing a wrong answer teaches nothing — the student has already shown they
 * do not have the material, and pressing is just repetition with a sharper
 * tone. Probing a nearly-right answer is where a viva earns its keep: the
 * student holds most of it, and the question finds the edge.
 *
 * So the band is deliberately narrow, and depth is capped. Three probes deep
 * on one concept stops being an examination and becomes an interrogation.
 */
create or replace function public.should_follow_up(p_question_id uuid)
returns table (should boolean, depth integer, reason text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user     uuid := auth.uid();
  v_question public.question%rowtype;
  v_score    numeric;
  v_gaps     integer;
  v_depth    integer := 0;
  v_cursor   uuid;
begin
  select * into v_question from public.question where id = p_question_id;
  if not found or v_question.user_id is distinct from v_user then
    return query select false, 0, 'question not found';
    return;
  end if;

  select ev.composite_score,
         (select count(*) from public.evaluation_gap g where g.evaluation_id = ev.id)
    into v_score, v_gaps
    from public.evaluation ev
    join public.answer a on a.id = ev.answer_id
   where a.question_id = p_question_id
   order by ev.created_at desc
   limit 1;

  if v_score is null then
    return query select false, 0, 'not marked yet';
    return;
  end if;

  -- How deep this thread already runs.
  v_cursor := v_question.parent_question_id;
  while v_cursor is not null and v_depth < 10 loop
    v_depth := v_depth + 1;
    select parent_question_id into v_cursor
      from public.question where id = v_cursor;
  end loop;

  if v_depth >= 2 then
    return query select false, v_depth, 'already probed twice on this thread';
    return;
  end if;

  if v_gaps = 0 then
    return query select false, v_depth, 'nothing specific left to press on';
    return;
  end if;

  -- 40-75: knows most of it, missed something identifiable. Below that the
  -- answer was not close enough for a probe to teach anything; above it,
  -- there is no meaningful edge left to find.
  if v_score >= 40 and v_score < 75 then
    return query select true, v_depth, null::text;
  else
    return query select false, v_depth,
      case when v_score < 40 then 'answer was too far off to probe'
           else 'answer was strong enough to move on' end;
  end if;
end;
$$;

revoke all on function public.should_follow_up(uuid) from public, anon;
grant execute on function public.should_follow_up(uuid) to authenticated;

comment on function public.should_follow_up is
  'Decides whether the examiner presses on the previous answer. Only for near-miss answers with an identified gap, and never more than two probes deep.';
