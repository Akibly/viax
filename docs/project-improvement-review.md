# ViaX improvement review — 14 October 2026

## Scope and architecture

Reviewed the Flutter app, its Supabase repository, examiner and ingestion Edge Functions, provider adapter, Python retrieval/examiner services, grounding migration, existing tests, and CI. The mobile app calls Supabase Edge Functions directly; the FastAPI entry point currently exposes health/readiness routes. Changes to the deployed AI path therefore belong in the Edge Functions, not only in the Python implementation.

The existing evidence-on-paper identity remains the visual direction. This pass concentrates on the complete answer/practice/review path, responsive controls, and truthful recovery states. The launch-video project was not changed.

## Implemented

### AI and retrieval

- Validate all six rubric scores as finite numbers within 0–100. Missing scores no longer silently become zero.
- Require actionable feedback and source-backed explanations for deducted marks. Reject unsupported citation labels before saving the evaluation.
- Validate question expected points and passage citations before the grounding verifier runs; require all verifier citations to be valid.
- Supply the original expected answer points to the marking model. Prompts distinguish uploaded material and student answers from instructions, credit equivalent wording, and avoid requiring irrelevant examples.
- Replace random topic selection with deterministic priority based on mastery, due dates, and importance. Rotate away from the three most recent topics when alternatives exist, while preserving explicit concept selection. Include recent questions in generation context.
- Preserve the actual successful fallback model in question/evaluation provenance.
- Limit each chat candidate to 20 seconds and the fallback walk to a 60-second budget per chat call. Retrieval and separate verification still add to total request time; this is not a 60-second end-to-end guarantee.
- Parse balanced JSON objects with quoted-brace handling and ignore explicit reasoning blocks. Malformed model output can move to another candidate.
- Validate embedding count, indices, dimensions, finite values, and nonzero vectors. Restore response order by input index before associating vectors with source chunks.
- Resolve embedding configuration only for question retrieval, so marking and follow-ups do not unnecessarily require an embedding provider.
- Reject unsupported request methods, malformed JSON bodies, and oversized/non-string answers.

### App behavior and UI

- Request speech initialization when the student taps the microphone, instead of opening the permission flow as soon as the answer field appears.
- Disable empty/double submissions, freeze the submitted text during marking, stop dictation, and ignore late transcription updates. Typed answers remain available when speech setup fails.
- Add an explicit answer label and descriptive marking state. Move voice controls below the field so large text does not overlap the answer.
- Increase the mic target to 48 dp and expose its enabled state to accessibility services. Respect reduced motion in waveform, rubric, and navigation animation.
- Make concept labels wrap; place rubric labels above their bars with spoken score semantics; use theme-aware focus colors.
- Preserve structured Supabase errors, including insufficient-material refusals, instead of losing them in a generic transport exception.
- Carry concept IDs through questions and session answers. “Practise weakest” now starts a fresh sitting focused on the chosen weak concept.
- Recover from Home study-load failures, add a subject retry action, wait for pull-to-refresh completion, and clamp old/out-of-range exam dates before opening the picker.
- Restrict nested Back handlers to the active tab.

### Delivery

- Add offline Edge Function tests covering invalid scores, unsupported citations, JSON fallback, embedding ordering/validation, adaptive topic selection, and successful model provenance.
- Add Flutter answer-input regression coverage, including narrow width, enlarged text, empty answers, submission state, and preservation of typed text.
- Add Flutter analysis/tests and Edge Function type/tests to CI.
- Pin local Python selection to 3.12, matching CI, via `.python-version`.

## Validation and limits

- Flutter test suite: 31 passing tests.
- Flutter static analysis: no issues found.
- Android debug APK: successfully built with offline Gradle and JDK 17 (`app:assembleDebug`). Artifact: `mobile/build/app/outputs/flutter-apk/app-debug.apk`. This is a debug build, not a store release.
- Repaired corrupt cached APK/asset packaging by preserving the generated folders as backups and rebuilding. The final APK passes a full ZIP CRC check, installs on the Android emulator, and reaches onboarding. The emulator also showed launcher/System UI not-responding dialogs; this is limited startup evidence, not a complete native interaction review.
- Edge Function regression suite: 11 passing tests; examiner and ingestion entry points type-check.
- Focused Python chunking, examiner-contract, and ingestion-unit suites: 58 passing tests.
- The complete Python suite crashes inside the local Python 3.14 interpreter while importing Pydantic v1 through FastAPI. This is a native interpreter failure rather than a reported assertion failure. An isolated run with the installed Python 3.12 runtime could not resolve dependencies because PyPI requests timed out. CI already uses Python 3.12.
- Live provider accuracy, latency, database integration/RLS, production deployment, and the authenticated Android practice flow have not been verified by these offline tests. No connected Android device was available at the start; a temporary emulator was used for the installation/startup check.
- The repository was already entirely untracked. Files were edited in place; no commit or production deployment was made.

## Remaining release work

1. Run migrations and the database isolation/integration suite against a local Supabase stack. Exercise partial writes and simultaneous answers; the current REST flow still creates answer/evaluation/gap records in separate operations, and attempt numbering is count-based.
2. Calibrate scores against a human-reviewed answer set across several subjects, including equivalent phrasing, partially correct answers, and injection-like source text. Contract tests prove format and citation rules, not educational accuracy or semantic entailment.
3. Run the updated app on Android with light/dark themes, enlarged text, microphone denied/granted, interrupted connectivity, and nested Back navigation. Physical voice behavior needs a device check.
4. Review provider quota accounting: reservations are per logical examiner operation while fallback attempts may make several provider calls. The new timeout budget limits latency, not exact token usage.
5. The existing notification scheduler and account/settings flows need a separate live review, including notification tap routing, persistence, and signed-out behavior. Do not infer release readiness from compilation alone.
6. Android still uses `com.example.vivax` and the debug signing configuration for release builds. Choose the permanent application ID and supply the real release signing configuration before store distribution; this pass does not invent an identity or signing key.

Tooling note: Impeccable reported a stale design sidecar and no recorded build-path preference. These configuration files were not silently rewritten. A newer Impeccable version was reported available; tool updates are separate from the app changes.
