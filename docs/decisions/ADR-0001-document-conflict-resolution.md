# ADR-0001 — Resolution of the 14 specification conflicts

**Status:** Accepted · **Date:** 2026-09-02

## Context

The specification corpus (Master Proposal v2.0, PRD v1.0, SRS v1.0, System Architecture v1.0,
UI/UX Design Guide v1.0) contains 14 internal conflicts. The dominant pattern: the SRS was
written against the Master Proposal and never reconciled with the PRD's prioritisation, so
11 of its 29 requirements over-commit relative to what the build will ship.

## Resolution principle

Each document is authoritative over one thing:

| Document | Authoritative over |
|---|---|
| PRD | **Scope and priority** — it is the only document that reasons about time |
| SRS | **Behaviour** of what is in scope |
| System Architecture | **Structure** — schema, endpoints, layering |
| UI/UX Design Guide | **Surface** — tokens, motion, screen composition |
| Master Proposal | **Vision** — superseded on any specific by the four above |

## Decisions

| ID | Conflict | Decision |
|---|---|---|
| C-01 | SRS FR-3.4 "shall support four viva modes" vs PRD P0 = two modes | **Two modes (Practice, Examination) are P0.** Professor and Mock Interview are P1. FR-3.4 is annotated with priority. |
| C-02 | SRS FR-3.5 voice "shall" vs PRD P1 | **Voice is P1.** First item promoted if Days 1–8 finish clean. Schema carries `input_mode` from day one so no migration is needed to enable it. |
| C-03 | SRS §3.7 teacher dashboard "shall" vs PRD explicitly out of scope | **Out of scope.** FR-7.x moves to an SRS appendix marked P2. The `score_override` audit design is still specified now so `evaluation` is built immutable. |
| C-04 | PRD "<5s cold start to first question" vs SRS "<6s question generation" | **Both hold only if question 1 is never generated on the critical path.** Question 1 is pre-generated at session creation. Budgets restated as p95 on a defined device. |
| C-05 | Gap severity vocabulary differs three ways | **One source of truth:** `gap_severity` enum = `strong / minor / medium / critical`, with thresholds defined once in `app.domain.mastery` and every label derived from it. The prototype's "Strong" becomes a real enum value; "none" is dropped as meaningless. |
| C-06 | SRS FR-6.1–6.3 analytics/gamification "shall" vs PRD P1 | **Analytics P1 but cheap** once `concept_mastery_event` exists. Gamification deferred to Track B. |
| C-07 | SRS FR-5.5 push "shall" vs PRD P1 | **P1.** Requires a permission-priming screen that no document specifies; designed on Day 13. |
| C-08 | Readiness card: Proposal specifies a letter-grade prediction; SRS and prototype omit it | **Dropped deliberately.** A predicted letter grade cannot be validated against any ground truth this product has. Recorded so it reads as a decision, not an oversight. |
| C-09 | "Technical Vocabulary" vs "Vocabulary" | **`technical_vocabulary`** as the column name; "Vocabulary" as the display label. |
| C-10 | Same citation (page 42) used for two different concepts across docs | Demo data regenerated from real retrievals. No product impact. |
| C-11 | 100 MB/file upload limit vs "free/low-tier quotas" constraint | **25 MB and 300 pages per file**, enforced server-side, with the reason stated in the error. |
| C-12 | PRD requires Concept Graph → focused practice in 1 tap; `POST /sessions` has no concept parameter | **`POST /v1/sessions` accepts `concept_ids[]`.** Without it the PRD's own success metric is unreachable. |
| C-13 | Offline Practice Mode promised in three documents | **Cannot evaluate an answer without an LLM.** Redefined as **Offline Revision**: pre-generated question packs, local self-assessment against a revealed model answer, answers queued and evaluated on reconnect. Track B. |
| C-14 | Proposal §27 vs PRD §8 timeline | No conflict — verified consistent. |

## Consequences

- The SRS must be re-issued with priority annotations before it is shown to the evaluation
  panel; leaving 11 unqualified "shall" statements in the body is a commitment the build
  will not meet.
- `evaluation` is designed immutable from the start even though score override is out of
  scope, because retrofitting immutability is a data migration.
- Dropping the letter-grade prediction is the kind of decision that reads as a gap unless
  it is written down. It is written down here.
