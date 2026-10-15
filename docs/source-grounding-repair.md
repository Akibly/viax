# ViaX source-grounding repair

Status on 4 October 2026: local implementation checked; remote deployment and
verification are pending because the supplied Supabase management credential
returns HTTP 401. The current CLI login does not list the configured ViaX project
(`wbodrnjdaqnsnjipdrjm`). No remote records were changed during this repair.

## Changes

- Ingestion accepts a topic only when its name occurs in a substantial verbatim
  evidence quote found in the extracted notes. Study definitions use source excerpts.
- Reprocessing preserves existing passage IDs and historical citations.
- Retrieval uses ready, visible documents and evidence-backed topic links.
- Questions and expected answer points undergo an additional model grounding
  check. Unsupported results are refused, with no fallback citation.
- New questions expose a link to the cited note passage. Old questions are
  excluded from new evaluations and follow-ups until fresh questions are generated.
- Study topics, Home readiness and review items exclude unsupported topics.
- Unimplemented Professor and Mock interview modes are disabled.

## Deployment order

1. Restore access to the configured Supabase project and inspect the current
   uploaded document, extracted passages and question-source rows. The specific
   Additive Manufacturing question under `Jav` remains unverified.
2. Apply `20261002100000_grounded_question_integrity.sql` and verify the RPCs.
3. Deploy the `ingest` and `examine` functions.
4. Reprocess existing uploads to populate verified evidence. Older topic records
   remain stored but are excluded until backed by source evidence.
5. Build and install the updated mobile app only after its new RPC dependency
   is live. Exercise upload, topic extraction, question generation, source
   navigation, evaluation and follow-up using actual uploaded notes.

## Verification

- Flutter analysis: no issues.
- Mobile regression tests: seven passed (study startup, floating navigation,
  viva mode properties and session summary).
- Deno function type checking: passed.
- Evidence matching and PowerPoint extraction tests: two passed.
- SQL migration execution and live AI grounding: not yet verified.

The additional model check reduces unsupported questions but does not guarantee
semantic correctness. Live validation must compare the question and expected
answer against its displayed source passage.
