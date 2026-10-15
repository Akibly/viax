-- Cross-user isolation test.
--
-- Audit SEC-01 is the highest-severity finding in the report: the corpus
-- promises per-student isolation and never names a mechanism. This test is
-- the mechanism's proof. It runs in CI and fails the build if a student can
-- see another student's rows.
--
-- It deliberately asserts on every table that holds student data, rather than
-- a representative sample. A missed policy on one table is a full breach of
-- that table.

begin;
select plan(32);

-- ---------------------------------------------------------------------------
-- Fixtures: two students, each with a full data trail.
-- ---------------------------------------------------------------------------

\set alice '11111111-1111-1111-1111-111111111111'
\set bob   '22222222-2222-2222-2222-222222222222'

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
values
  (:'alice', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'alice@example.test', '', now(), now(), now(), '{}', '{"full_name":"Alice"}'),
  (:'bob',   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'bob@example.test',   '', now(), now(), now(), '{}', '{"full_name":"Bob"}');

-- The auth trigger should have created both profiles.
select is(
  (select count(*)::int from public.profile where id in (:'alice', :'bob')),
  2,
  'on_auth_user_created creates a profile for each new auth user'
);

-- Alice's data trail, created as the backend would (service_role / owner).
insert into public.subject (id, user_id, name)
values ('a0000000-0000-0000-0000-000000000001', :'alice', 'Operating Systems');

insert into public.document (id, subject_id, user_id, filename, storage_path,
                             mime_type, byte_size, page_count, content_hash, status)
values ('a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001',
        :'alice', 'os-notes.pdf', 'alice/os-notes.pdf', 'application/pdf',
        1048576, 60, 'sha256:alice-os', 'ready');

insert into public.chunk (id, document_id, subject_id, user_id, chunk_index, content, page_number)
values ('a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000001', :'alice', 0,
        'A deadlock requires mutual exclusion, hold and wait, no preemption, and circular wait.', 42);

insert into public.concept (id, subject_id, user_id, canonical_name, aliases)
values ('a0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001',
        :'alice', 'Deadlock', array['Deadlocks','Dead lock']);

insert into public.concept_chunk (concept_id, chunk_id, user_id)
values ('a0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000003', :'alice');

insert into public.viva_session (id, user_id, subject_id, mode, rubric_version, policy_version)
values ('a0000000-0000-0000-0000-000000000005', :'alice', 'a0000000-0000-0000-0000-000000000001',
        'practice', 'rubric-v1', 'adaptive-v1');

insert into public.question (id, session_id, user_id, concept_id, ordinal,
                             difficulty_level, text, prompt_version, model)
values ('a0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000005',
        :'alice', 'a0000000-0000-0000-0000-000000000004', 1, 1,
        'What is a deadlock in an operating system?', 'qgen-v1', 'claude-opus-5');

insert into public.question_source_chunk (question_id, chunk_id, rank)
values ('a0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000003', 1);

insert into public.answer (id, question_id, user_id, text, input_mode, duration_ms)
values ('a0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000006',
        :'alice', 'Two processes waiting on each other forever.', 'typed', 21000);

insert into public.evaluation (id, answer_id, user_id, concept_accuracy, completeness,
                               technical_vocabulary, logical_flow, depth, examples_used,
                               composite_score, feedback, model, prompt_version, rubric_version)
values ('a0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000007',
        :'alice', 70, 45, 60, 65, 40, 30, 58,
        'Correct as far as it goes, but the four necessary conditions are missing.',
        'claude-opus-5', 'eval-v1', 'rubric-v1');

insert into public.evaluation_gap (id, evaluation_id, user_id, concept_id, label, severity)
values ('a0000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000008',
        :'alice', 'a0000000-0000-0000-0000-000000000004',
        'The four necessary conditions for deadlock', 'critical');

insert into public.evaluation_citation (gap_id, chunk_id, user_id)
values ('a0000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000003', :'alice');

insert into public.concept_mastery (user_id, subject_id, concept_id, mastery_pct, gap_severity, due_at)
values (:'alice', 'a0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000004', 34, 'critical', now());

insert into public.concept_mastery_event (user_id, subject_id, concept_id, answer_id,
                                          evaluation_id, prior_mastery, new_mastery, rating)
values (:'alice', 'a0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000007',
        'a0000000-0000-0000-0000-000000000008', 0, 34, 2);

-- ---------------------------------------------------------------------------
-- Bob must see nothing of Alice's.
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', :'bob', 'role', 'authenticated')::text, true);

select is((select count(*)::int from public.subject),               0, 'bob sees no subjects of alice');
select is((select count(*)::int from public.document),              0, 'bob sees no documents of alice');
select is((select count(*)::int from public.chunk),                 0, 'bob sees no chunks of alice — the uploaded notes');
select is((select count(*)::int from public.concept),               0, 'bob sees no concepts of alice');
select is((select count(*)::int from public.concept_chunk),         0, 'bob sees no concept_chunk of alice');
select is((select count(*)::int from public.viva_session),          0, 'bob sees no sessions of alice');
select is((select count(*)::int from public.question),              0, 'bob sees no questions of alice');
select is((select count(*)::int from public.question_source_chunk), 0, 'bob sees no question grounding of alice');
select is((select count(*)::int from public.answer),                0, 'bob sees no answers of alice');
select is((select count(*)::int from public.evaluation),            0, 'bob sees no evaluations of alice — the scores');
select is((select count(*)::int from public.evaluation_gap),        0, 'bob sees no gaps of alice');
select is((select count(*)::int from public.evaluation_citation),   0, 'bob sees no citations of alice');
select is((select count(*)::int from public.concept_mastery),       0, 'bob sees no mastery of alice');
select is((select count(*)::int from public.concept_mastery_event), 0, 'bob sees no mastery history of alice');
select is((select count(*)::int from public.revision_queue),        0, 'bob sees no revision queue of alice');
select is((select count(*)::int from public.profile where id = :'alice'), 0, 'bob cannot read alice''s profile');

-- Bob cannot write into Alice's namespace either.
select throws_ok(
  format('insert into public.subject (user_id, name) values (%L, %L)', :'alice', 'Stolen Subject'),
  '42501',
  null,
  'bob cannot create a subject owned by alice'
);

-- ---------------------------------------------------------------------------
-- Alice sees exactly her own.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims',
  json_build_object('sub', :'alice', 'role', 'authenticated')::text, true);

select is((select count(*)::int from public.subject),               1, 'alice sees her subject');
select is((select count(*)::int from public.chunk),                 1, 'alice sees her chunk');
select is((select count(*)::int from public.evaluation),            1, 'alice sees her evaluation');
select is((select count(*)::int from public.concept_mastery_event), 1, 'alice sees her mastery history');
select is((select count(*)::int from public.revision_queue),        1, 'alice sees her revision queue');
select is(
  (select bucket from public.revision_queue limit 1),
  'today',
  'a concept due now falls in the today bucket'
);

-- Alice may rename her own subject (SRS FR-2.1).
select lives_ok(
  $$update public.subject set name = 'Operating Systems II' where user_id = auth.uid()$$,
  'alice can rename her own subject'
);

-- ---------------------------------------------------------------------------
-- Anonymous callers get nothing. VivaX has no public content.
-- ---------------------------------------------------------------------------

reset role;
set local role anon;
select set_config('request.jwt.claims', json_build_object('role','anon')::text, true);

select throws_ok(
  'select count(*) from public.subject',
  '42501',
  null,
  'anon has no privilege on subject'
);
select throws_ok(
  'select count(*) from public.chunk',
  '42501',
  null,
  'anon has no privilege on chunk'
);

-- ---------------------------------------------------------------------------
-- Structural guarantees, checked as the owner (service_role bypasses RLS, so
-- these must hold by trigger, not by policy).
-- ---------------------------------------------------------------------------

reset role;

-- restrict_violation, raised by app.reject_mutation()
select throws_ok(
  $$update public.evaluation set composite_score = 100
    where id = 'a0000000-0000-0000-0000-000000000008'$$,
  '23001', null,
  'evaluation is append-only even for a privileged role'
);

select throws_ok(
  $$delete from public.concept_mastery_event$$,
  '23001', null,
  'mastery history cannot be deleted, so the improvement curve cannot be rewritten'
);

-- A gap with no citation must not be committable. The constraint is deferred,
-- so the check is forced with SET CONSTRAINTS inside a function — pgTAP runs
-- each throws_ok in a subtransaction, which unwinds the pending insert too.
create function pg_temp.commit_uncited_gap() returns void
language plpgsql as $fn$
begin
  insert into public.evaluation_gap (evaluation_id, user_id, label)
  values ('a0000000-0000-0000-0000-000000000008',
          '11111111-1111-1111-1111-111111111111', 'Uncited gap');
  set constraints public.evaluation_gap_must_be_cited immediate;
end;
$fn$;

select throws_ok(
  'select pg_temp.commit_uncited_gap()',
  '23000', null,
  'a flagged gap with no citation is rejected — the PRD 100%-cited metric is enforced, not aspirational'
);

-- A citation must point at a chunk that actually grounded the question.
insert into public.document (id, subject_id, user_id, filename, storage_path,
                             mime_type, byte_size, content_hash, status)
values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
        :'alice', 'other.pdf', 'alice/other.pdf', 'application/pdf', 1024, 'sha256:other', 'ready');

insert into public.chunk (id, document_id, subject_id, user_id, chunk_index, content, page_number)
values ('b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001', :'alice', 0, 'Unrelated passage.', 7);

select throws_ok(
  $$insert into public.evaluation_citation (gap_id, chunk_id, user_id)
    values ('a0000000-0000-0000-0000-000000000009',
            'b0000000-0000-0000-0000-000000000002',
            '11111111-1111-1111-1111-111111111111')$$,
  '23000', null,
  'a citation to a chunk that was never retrieved is rejected — hallucinated citations fail a constraint'
);

-- Denormalised ownership cannot be forged.
select throws_ok(
  format($$insert into public.chunk (document_id, subject_id, user_id, chunk_index, content)
           values ('a0000000-0000-0000-0000-000000000002',
                   'a0000000-0000-0000-0000-000000000001', %L, 99, 'smuggled')$$, :'bob'),
  '23514', null,
  'chunk.user_id cannot disagree with its parent document'
);

select * from finish();
rollback;
