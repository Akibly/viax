# ViaX web deployment — 15 October 2026

Production frontend: https://viax-iota.vercel.app

Vercel project: `git-syn-admin/viax`

## Status

The Flutter release web build is deployed and publicly serves the application. Desktop and phone onboarding were visually inspected. Browser loading assets are served locally, with a branded loading/retry state. Onboarding scrolls on short screens; Android notifications are skipped on web; sign-up now explains email confirmation.

The unavailable original backend has been replaced with the user-supplied Viax project `yqmxzjkebqtfjlopzgze`. All 29 migrations are applied, `examine` and `ingest` are deployed, and guest authentication is enabled. The production site URL and authentication redirect allowlist point to Vercel. Email confirmation remains enabled.

The fresh database migration exposed a return-type mismatch in `subject_readiness`. The grounded readiness migration now preserves the existing effective mastery and decay columns. The failed transaction rolled back; the corrected migration set committed successfully, including migration history. The database pooler timed out, so migrations were applied through the Supabase management SQL endpoint.

NVIDIA chat is configured in Edge Function secrets with `nvidia/nemotron-3.5-lightning-30b-a3b`. Document processing and question retrieval now use `nvidia/llama-nemotron-embed-vl-1b-v2` with an explicit 1024-dimension request, using the same NVIDIA secret. A live embedding request returned 1024 dimensions. OpenRouter is optional and is not required for this deployment. No private access token or provider key was written into the application or deployment files.

Live browser verification: guest sign-in returned HTTP 200, authenticated database reads returned HTTP 200, and the empty study home opened. Email/password login with a real user account has not been exercised. The new project has a separate user database from the unavailable original project. Home data reads now run concurrently to reduce timeouts on slow connections.

## Rebuild and publish

From `mobile`, build with the correct public configuration:

```powershell
flutter build web --release --no-pub --no-web-resources-cdn --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_KEY=YOUR-PUBLISHABLE-KEY
npx vercel deploy build/web --prod --yes --archive=tgz
```

Only `build/web` is uploaded; backend environment files are not part of this deployment. The Supabase service-role key and AI provider keys must remain server-side. The Vercel configuration is maintained in `mobile/web/vercel.json` and copied by Flutter into the build.

The initial file upload failed on network transport; the archive upload completed successfully. Vercel hosting does not deploy Supabase migrations or Edge Functions. Those require the correct ViaX project and a separate deployment.

Configure the Supabase authentication site URL and permitted redirects for the production origin when the correct backend is available. Email recovery and confirmation flows need live verification with that project.
