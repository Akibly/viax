-- Table privileges for the `authenticated` role.
--
-- The RLS migration wrote row policies for every table but granted only
-- SELECT (and, on `subject`, INSERT/UPDATE). Postgres checks the grant first
-- and the policy second, so a table with a perfect INSERT policy and no
-- INSERT grant rejects every write with `42501 permission denied` — before
-- the policy is ever consulted.
--
-- The effect was that a student could create a subject and nothing else: no
-- upload, no session, no answer, no evaluation. The policies were never
-- reached, which is why the omission survived review.
--
-- Grants are issued per table rather than schema-wide, because the *shape* of
-- what each table allows is part of the design:
--
--   * no DELETE where a row is soft-deleted (`deleted_at`) — the history is
--     the point, and a hard delete would break the audit trail;
--   * no UPDATE or DELETE on the append-only tables, matching the
--     `app.reject_mutation` triggers already guarding them. A grant that
--     contradicts a trigger just moves the error later.
--
-- RLS still decides *which* rows. This decides which verbs exist at all.

-- Owned content the student creates and revises.
grant select, insert, update on public.document          to authenticated;
grant select, insert, update on public.concept           to authenticated;
grant select, insert, update on public.concept_mastery   to authenticated;
grant select, insert, update on public.viva_session      to authenticated;
grant select, insert, update on public.ingestion_job     to authenticated;

-- Derived during ingestion. Written once, replaced by re-ingesting, so
-- DELETE is allowed here specifically: re-processing a document must be able
-- to clear the chunks it previously produced.
grant select, insert, delete on public.chunk                 to authenticated;
grant select, insert, delete on public.concept_chunk         to authenticated;
grant select, insert, delete on public.concept_edge          to authenticated;
grant select, insert, delete on public.question_source_chunk to authenticated;

-- Examination records. Insert-only: an answer already given and a question
-- already asked are facts, and editing them would let a student rewrite the
-- exam after seeing the mark.
grant select, insert on public.question              to authenticated;
grant select, insert on public.answer                to authenticated;
grant select, insert on public.evaluation            to authenticated;
grant select, insert on public.evaluation_gap        to authenticated;
grant select, insert on public.evaluation_citation   to authenticated;
grant select, insert on public.concept_mastery_event to authenticated;

-- The schedule churns constantly as items are answered and rescheduled.
grant select, insert, update, delete on public.revision_queue to authenticated;

-- The row is created by app.handle_new_user; the student may edit their own
-- display name and exam date but never insert a second profile.
grant select, update on public.profile to authenticated;

-- Sequences are only needed where a table uses one; none here do (all keys
-- are uuid defaults), so no sequence grants are issued deliberately rather
-- than by omission.
