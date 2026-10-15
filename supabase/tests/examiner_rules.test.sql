-- Rules the examiner must obey, tested without spending a model call.
--
-- The Edge Functions had no automated tests at all — extraction, retrieval,
-- grounding, marking, adaptation and probing were verified only by me running
-- them by hand. That does not scale and it does not survive a refactor.
--
-- Everything the model does not decide is testable in SQL: the difficulty
-- ladder, the follow-up rule, citation provenance, and every ownership
-- boundary. Fabricated marks drive the real query paths, so these exercise
-- the same joins production uses.
--
-- Each block ends by raising, which rolls its fixtures back — `evaluation` is
-- append-only, so deleting a test user cascades into a table that refuses
-- DELETE. A message starting PASS is success; anything else is a failure.
--
-- Run: python scratchpad/run_sql_tests.py

-- ── The difficulty ladder ────────────────────────────────────────────────
do $$
declare
  v_user     uuid := gen_random_uuid();
  v_subject  uuid;
  v_concept  uuid;
  v_session  uuid;
  v_question uuid;
  v_answer   uuid;
  v_ordinal  integer := 0;
  v_level    integer;
  v_climbed  integer[];
  v_fell     integer[];

begin
  insert into auth.users (id, email, aud, role)
    values (v_user, 'ladder@test.invalid', 'authenticated', 'authenticated');
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user::text)::text, true);

  insert into public.subject (user_id, name)
    values (v_user, 'Ladder') returning id into v_subject;
  insert into public.concept (subject_id, user_id, canonical_name)
    values (v_subject, v_user, 'Deadlock') returning id into v_concept;
  insert into public.viva_session (user_id, subject_id, mode, rubric_version,
                                   policy_version)
    values (v_user, v_subject, 'practice', 'v1', 'v1') returning id into v_session;

  if app.next_difficulty(v_subject, null) <> 2 then
    raise exception 'a student with no history should open at level 2, got %',
      app.next_difficulty(v_subject, null);
  end if;

  -- Three strong answers should climb, one rung at a time.
  for i in 1..3 loop
    v_ordinal := v_ordinal + 1;
    v_level := app.next_difficulty(v_subject, null);
    v_climbed := coalesce(v_climbed, '{}') || v_level;
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model)
      values (v_session, v_user, v_concept, v_ordinal, v_level,
              'q' || v_ordinal, 'v1', 'test') returning id into v_question;
    insert into public.answer (question_id, user_id, text, attempt_number)
      values (v_question, v_user, 'a', 1) returning id into v_answer;
    insert into public.evaluation (answer_id, user_id, concept_accuracy,
        completeness, technical_vocabulary, logical_flow, depth, examples_used,
        composite_score, feedback, model, prompt_version, rubric_version)
      values (v_answer, v_user, 80, 80, 80, 80, 80, 80, 78, 'ok', 'test',
              'v1', 'v1');
  end loop;

  if app.next_difficulty(v_subject, null) <= v_climbed[1] then
    raise exception 'strong answers must raise difficulty: opened at %, now %',
      v_climbed[1], app.next_difficulty(v_subject, null);
  end if;

  -- Then two failures should bring it back down.
  for i in 1..2 loop
    v_ordinal := v_ordinal + 1;
    v_level := app.next_difficulty(v_subject, null);
    v_fell := coalesce(v_fell, '{}') || v_level;
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model)
      values (v_session, v_user, v_concept, v_ordinal, v_level,
              'q' || v_ordinal, 'v1', 'test') returning id into v_question;
    insert into public.answer (question_id, user_id, text, attempt_number)
      values (v_question, v_user, 'a', 1) returning id into v_answer;
    insert into public.evaluation (answer_id, user_id, concept_accuracy,
        completeness, technical_vocabulary, logical_flow, depth, examples_used,
        composite_score, feedback, model, prompt_version, rubric_version)
      values (v_answer, v_user, 5, 5, 5, 5, 5, 5, 6, 'weak', 'test', 'v1', 'v1');
  end loop;

  if app.next_difficulty(v_subject, null) >= v_fell[1] then
    raise exception 'weak answers must lower difficulty: was %, now %',
      v_fell[1], app.next_difficulty(v_subject, null);
  end if;

  raise exception 'PASS ladder: climbed % then fell %', v_climbed, v_fell;
end $$;

-- ── When the examiner presses ────────────────────────────────────────────
do $$
declare
  v_user     uuid := gen_random_uuid();
  v_subject  uuid;
  v_concept  uuid;
  v_session  uuid;
  v_doc      uuid;
  v_chunk    uuid;

begin
  insert into auth.users (id, email, aud, role)
    values (v_user, 'probe@test.invalid', 'authenticated', 'authenticated');
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user::text)::text, true);

  insert into public.subject (user_id, name)
    values (v_user, 'Probe') returning id into v_subject;
  insert into public.document (subject_id, user_id, filename, storage_path,
      mime_type, byte_size, content_hash)
    values (v_subject, v_user, 'p.pdf', 'p/p.pdf', 'application/pdf', 10,
            repeat('b', 64)) returning id into v_doc;
  insert into public.concept (subject_id, user_id, canonical_name)
    values (v_subject, v_user, 'Deadlock') returning id into v_concept;
  insert into public.chunk (document_id, subject_id, user_id, chunk_index,
      content, page_number)
    values (v_doc, v_subject, v_user, 0, 'grounding text', 1)
    returning id into v_chunk;
  insert into public.viva_session (user_id, subject_id, mode, rubric_version,
      policy_version)
    values (v_user, v_subject, 'practice', 'v1', 'v1') returning id into v_session;

  -- A near-miss with a cited gap: the examiner should press.
  declare
    v_q uuid; v_a uuid; v_e uuid; v_g uuid; v_should boolean;
  begin
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model)
      values (v_session, v_user, v_concept, 1, 2, 'near miss', 'v1', 'test')
      returning id into v_q;
    insert into public.question_source_chunk (question_id, chunk_id, rank)
      values (v_q, v_chunk, 1);
    insert into public.answer (question_id, user_id, text, attempt_number)
      values (v_q, v_user, 'partly right', 1) returning id into v_a;
    insert into public.evaluation (answer_id, user_id, concept_accuracy,
        completeness, technical_vocabulary, logical_flow, depth, examples_used,
        composite_score, feedback, model, prompt_version, rubric_version)
      values (v_a, v_user, 60, 40, 60, 60, 40, 30, 55, 'partial', 'test',
              'v1', 'v1') returning id into v_e;
    perform public.record_gap(v_e, 'Missing bound', 'no number given',
                              array[v_chunk]);

    select should into v_should from public.should_follow_up(v_q);
    if not v_should then
      raise exception 'a 55 with a cited gap must be probed';
    end if;
  end;

  -- A hopeless answer: pressing teaches nothing.
  declare
    v_q uuid; v_a uuid; v_e uuid; v_should boolean; v_reason text;
  begin
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model)
      values (v_session, v_user, v_concept, 2, 2, 'lost', 'v1', 'test')
      returning id into v_q;
    insert into public.answer (question_id, user_id, text, attempt_number)
      values (v_q, v_user, 'no idea', 1) returning id into v_a;
    insert into public.evaluation (answer_id, user_id, concept_accuracy,
        completeness, technical_vocabulary, logical_flow, depth, examples_used,
        composite_score, feedback, model, prompt_version, rubric_version)
      values (v_a, v_user, 5, 5, 5, 5, 5, 5, 8, 'wrong', 'test', 'v1', 'v1')
      returning id into v_e;

    select should, reason into v_should, v_reason
      from public.should_follow_up(v_q);
    if v_should then
      raise exception 'an 8 must not be probed — the student has not got it';
    end if;
  end;

  -- A strong answer: nothing left to find.
  declare
    v_q uuid; v_a uuid; v_should boolean;
  begin
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model)
      values (v_session, v_user, v_concept, 3, 2, 'strong', 'v1', 'test')
      returning id into v_q;
    insert into public.answer (question_id, user_id, text, attempt_number)
      values (v_q, v_user, 'complete', 1) returning id into v_a;
    insert into public.evaluation (answer_id, user_id, concept_accuracy,
        completeness, technical_vocabulary, logical_flow, depth, examples_used,
        composite_score, feedback, model, prompt_version, rubric_version)
      values (v_a, v_user, 90, 90, 90, 90, 90, 90, 90, 'good', 'test',
              'v1', 'v1');

    select should into v_should from public.should_follow_up(v_q);
    if v_should then
      raise exception 'a 90 must not be probed — move on';
    end if;
  end;

  raise exception 'PASS follow-up: presses near-misses, skips failures and passes';
end $$;

-- ── A probe cannot drift ─────────────────────────────────────────────────
do $$
declare
  v_user    uuid := gen_random_uuid();
  v_subject uuid;
  v_c1 uuid; v_c2 uuid;
  v_s1 uuid; v_s2 uuid;
  v_parent uuid;
  v_caught boolean;
begin
  insert into auth.users (id, email, aud, role)
    values (v_user, 'lineage@test.invalid', 'authenticated', 'authenticated');
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_user::text)::text, true);

  insert into public.subject (user_id, name)
    values (v_user, 'Lineage') returning id into v_subject;
  insert into public.concept (subject_id, user_id, canonical_name)
    values (v_subject, v_user, 'Deadlock') returning id into v_c1;
  insert into public.concept (subject_id, user_id, canonical_name)
    values (v_subject, v_user, 'Paging') returning id into v_c2;
  insert into public.viva_session (user_id, subject_id, mode, rubric_version,
      policy_version)
    values (v_user, v_subject, 'practice', 'v1', 'v1') returning id into v_s1;
  insert into public.viva_session (user_id, subject_id, mode, rubric_version,
      policy_version)
    values (v_user, v_subject, 'practice', 'v1', 'v1') returning id into v_s2;

  insert into public.question (session_id, user_id, concept_id, ordinal,
      difficulty_level, text, prompt_version, model)
    values (v_s1, v_user, v_c1, 1, 2, 'parent', 'v1', 'test')
    returning id into v_parent;

  -- Different concept: refused.
  v_caught := false;
  begin
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model, parent_question_id)
      values (v_s1, v_user, v_c2, 2, 3, 'drifted', 'v1', 'test', v_parent);
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'a probe must not wander to another concept';
  end if;

  -- Different sitting: refused.
  v_caught := false;
  begin
    insert into public.question (session_id, user_id, concept_id, ordinal,
        difficulty_level, text, prompt_version, model, parent_question_id)
      values (v_s2, v_user, v_c1, 1, 3, 'other sitting', 'v1', 'test', v_parent);
  exception when others then v_caught := true;
  end;
  if not v_caught then
    raise exception 'a probe must stay in the same sitting';
  end if;

  -- Same concept, same sitting: allowed.
  insert into public.question (session_id, user_id, concept_id, ordinal,
      difficulty_level, text, prompt_version, model, parent_question_id)
    values (v_s1, v_user, v_c1, 3, 3, 'valid probe', 'v1', 'test', v_parent);

  raise exception 'PASS lineage: probes cannot change concept or sitting';
end $$;

-- ── Forgetting ───────────────────────────────────────────────────────────
do $$
begin
  if app.decayed_mastery(80, 10, now()) < 79 then
    raise exception 'a just-reviewed concept must not have decayed';
  end if;
  if app.decayed_mastery(80, 1, now() - interval '14 days') > 1 then
    raise exception 'a fragile concept must fade to near nothing in a fortnight';
  end if;
  if app.decayed_mastery(80, 30, now() - interval '3 days') < 65 then
    raise exception 'a well-known concept must barely move in three days';
  end if;
  if app.decayed_mastery(null, 10, now()) is not null then
    raise exception 'an unexamined concept must not decay into a score';
  end if;
  raise exception 'PASS decay: fades with stability, leaves unexamined alone';
end $$;
