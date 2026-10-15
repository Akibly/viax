# Contributing to ViaX

Bug reports, documentation improvements, and pull requests are welcome.

1. Open an issue describing the problem or proposed change.
2. Fork the repository and create a focused branch.
3. Use your own Supabase project and AI provider credentials.
4. Explain your changes, how you checked them, and any known limitations in your pull request.

Never commit private keys, environment files, user uploads, database exports, or authentication tokens. Redact personal information from screenshots and logs.

Follow the existing Dart, TypeScript, Python, and SQL conventions. Database changes belong in a new Supabase migration. Keep document ownership checks, row-level security, source citations, and usage limits intact.

The CI workflow describes the project's automated checks. Tests that call external model providers can consume credits; use local fixtures unless you deliberately opt into live evaluation.

By contributing, you agree that your contributions will be licensed under this project's MIT license.
