# VivaX — Build Plan

> Derived from the pre-implementation audit (47 findings, 14 document conflicts).
> Audit report: https://claude.ai/code/artifact/8e057a17-a11f-4e8d-a3c0-dde410dd302d

## Guiding principle

**Cut breadth, buy depth.** The product's thesis is that it *assesses* rather than chats.
An assessment product whose accuracy is unmeasured is a chatbot with a number on it.
Therefore the calibration work (Day 6–7) is not a nice-to-have — it is the deliverable
that everything else supports.

## Scope decision (assumed; reversible)

Cut from the 15-day build, per audit recommendation:

| Cut | Reason | Where it goes |
|---|---|---|
| Teacher dashboard | Different buyer, compliance surface, PRD §5.3 already excludes it | Track B |
| Gamification (XP/badges/leaderboard) | Retention garnish on a product with no retention problem yet | Track B |
| Web dashboard (beyond a static report page) | Two clients, one developer, 15 days | Track B |
| Offline Practice Mode | Cannot evaluate an answer without an LLM (audit AI-06) | Redefined as *Offline Revision*, Track B |

Added, that the original plan did not have:

- A **gold set** with a published human-agreement number (Day 6–7)
- A **real concept graph** with canonical concepts and prerequisite edges (Day 4)
- **Hybrid retrieval** (vector + BM25 + rerank) instead of dense-only (Day 3)
- **FSRS** scheduling instead of a four-value enum (Day 11)

Voice stays out unless Days 1–8 finish clean; it is the first item promoted.

## Status

| Day | Phase | State |
|---|---|---|
| 1 | Foundations: schema, RLS, config, logging, CI | **done** |
| 2 | Ingestion: jobs, storage, extraction, chunking, embeddings | **done** |
| 3 | Retrieval: hybrid + rerank + coverage guard | **next** |
| 4 | Concept extraction with prerequisite edges | pending |
| 5 | Question generation, 5 levels, grounded | pending |
| 6 | Gold set construction | pending |
| 7 | Evaluation engine + calibration gate | pending |
| 8 | Adaptive policy + session state machine | pending |
| 9–10 | Flutter core loop | pending |
| 11 | Gap detection + FSRS revision planner | pending |
| 12 | Readiness score + analytics | pending |
| 13 | First-run, empty/error states, deletion/export | pending |
| 14 | A11y, cost caps, observability, perf | pending |
| 15 | Eval suite run, demo, docs | pending |

## Day 1 — Foundations (detail)

Decisions that get more expensive every day are settled here, before any feature code.

- [x] Repository structure, toolchain verified
- [x] Architecture decision records for the resolved document conflicts
- [x] Schema v1 — including the four things the audit found missing:
      `concept` entity, `concept_mastery_event` history, FSRS fields, citation foreign keys
- [x] RLS on every table in the first migration, deny-by-default
- [x] Cross-user isolation test (pgTAP) — fails the build if a student can read another's rows
- [x] Backend config with fail-loud environment validation
- [x] Structured logging with request IDs
- [x] Health and readiness probes
- [x] CI pipeline

## Non-negotiables carried from the audit

These are enforced by structure, not by discipline:

1. **RLS in migration 001.** Never retrofitted. A CI test asserts cross-user reads return zero rows.
2. **Citations are foreign keys**, never free text. The model may only cite chunk IDs from the
   retrieved set; the server resolves them to document + page. A fabricated citation is
   structurally impossible, not merely discouraged.
3. **Mastery is append-only.** `concept_mastery_event` is the source of truth;
   current mastery is a projection. Overwriting a number destroys the analytics.
4. **Revision is scheduled by timestamp**, not by an enum. The four tabs are views over `due_at`.
5. **No user IDs in URL paths.** Identity comes from the token: `/v1/me/...`.
6. **Question creation is a POST and is idempotent** on (session, ordinal).
7. **Retrieved chunks are data, never instructions.** The evaluator returns a constrained
   schema; scores are computed server-side from that schema, never parsed from prose.

## Credentials needed

Supabase project URL, anon key, and service-role key — needed to run migrations against a
live project. Local development uses `supabase start` (Docker) and needs nothing.

## Day 1 — verified, not asserted

Every claim below was executed, not written down and hoped for.

| Check | Command | Result |
|---|---|---|
| 5 migrations apply from scratch | `supabase db reset` | clean, first run |
| Cross-user isolation + structural guarantees | `supabase test db` | **32/32 pass** |
| Backend unit tests | `pytest` | 12/12 pass |
| Lint | `ruff check app tests` | clean |
| API boots against the live database | `uvicorn app.main:app` | `/v1/health` 200, `/v1/ready` 200, db 3.85 ms |

What the 32 database tests actually prove:

- Bob sees **zero rows** of Alice's across all 14 student-data tables and the
  revision view, and cannot insert a subject owned by her.
- `anon` has no privilege on any table. VivaX has no public content.
- `evaluation` and `concept_mastery_event` reject UPDATE and DELETE **even as
  a privileged role** — the backend runs as service_role, which bypasses RLS,
  so immutability is a trigger rather than a policy.
- A flagged gap with **no citation cannot be committed**. The PRD's
  "100% of flagged gaps are cited" is a constraint, not an aspiration.
- A citation to a chunk that **did not ground the question** is rejected.
  Hallucinated citations fail a trigger before a student can check page 42.
- A chunk whose `user_id` disagrees with its parent document is rejected, so
  the denormalised columns the RLS policies read cannot drift.

## Local development

The default Supabase ports were already taken by another project on this
machine, so this one runs on 553xx:

    supabase start          # api 55321, db 55322, studio 55323
    supabase db reset       # apply migrations
    supabase test db        # isolation suite

    cd backend
    ./.venv/Scripts/python.exe -m pytest
    ./.venv/Scripts/python.exe -m uvicorn app.main:app --reload --port 8099

## Day 2 — verified, not asserted

| Check | Result |
|---|---|
| 6 migrations apply from scratch | clean |
| `supabase test db` | 32/32 pass |
| `pytest` (unit + integration) | **73/73 pass** |
| `ruff check` | clean |
| `mypy app` | clean, 16 files |

Built:

- **Postgres-backed job queue** with `FOR UPDATE SKIP LOCKED`, leases, exponential
  backoff and a dead-letter state. A separate broker would buy throughput the product
  does not need at the cost of an operational surface it cannot afford.
- **Private storage bucket** with per-user path prefixes enforced by storage RLS, and
  short-lived signed URLs. Object keys are constructed in exactly one place because the
  first path segment *is* the security boundary.
- **Structure-aware chunking** — splits on headings first, size second, and every chunk
  carries the page it starts on so every chunk can be cited.
- **Extraction** with distinguishable failures: a scan routes to OCR, a corrupt file
  fails, and every failure carries advice the student can act on.
- **Embedding providers** behind one protocol, with the test double refused outside tests.

Properties proved by test rather than asserted in a comment:

- **Two workers never claim the same job.** Verified with two real connections holding
  two open transactions — a single-session test cannot observe lock contention.
- **A killed worker's job is reclaimed** with backoff, and dies after `max_attempts`
  rather than retrying a poisonous document forever.
- **Embedding resumes rather than restarts.** After losing one vector of a document,
  a re-run re-embeds exactly one chunk — not all of them.
- **Re-running chunking is a no-op**, so a retry after a crash cannot duplicate or strand.
- **Chunk page numbers come from the source document**, not a counter, so a citation
  cannot send a student to the wrong page.

Three real bugs were found by these tests and fixed:

1. `reap_expired_leases` assigned a text literal to an enum column — with an empty
   `search_path` the CASE branches resolved as `text` and the function failed at runtime.
2. Short documents with a perfectly good text layer were misrouted to OCR by an
   average-characters-per-page heuristic. Replaced with a per-page text-layer test.
3. The chunker folded a page-42 section into a page-41 chunk, corrupting the citation
   page. Merging is now refused across a page or heading boundary.
