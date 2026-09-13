# Repository Guidelines

Flutter lives in lib, SQLite in lib/database.dart, encrypted backups in lib/backup files, mobile auth in lib/session.dart, and Stripe entitlement state in lib/subscription.dart. FastAPI lives in backend, its Neon schema in backend/migrations, Worker proxy code in cloudflare, tests in test and backend/tests, and product decisions in docs.

Use the pinned SDK with fvm flutter pub get, fvm flutter analyze and fvm flutter test. Run Python tests with backend\.venv\Scripts\python.exe -m pytest -q backend. Build Android with an explicit direct or play flavor and matching JALE_DISTRIBUTION define.

Use two-space Dart formatting, strict types, integer cents, ISO dates, snake_case SQL and short Conventional Commit subjects. Each business-rule fix needs a regression test. Never commit credentials, signing files, customer backups or production database URLs.
