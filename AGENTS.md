# Repository Guidelines

## Project Structure & Module Organization

This is an Expo/React Native Android-first app. `App.tsx` wires the providers; product UI lives in `src/JaleApp.tsx`. Keep business rules in `src/domain.ts`, SQLite access and migrations in `src/database.ts`, PDF rendering in `src/documents.ts`, encrypted import/export in `src/backup*.ts`, and Play Billing state in `src/subscription.tsx`. Unit tests live in `tests/`; Expo config plugins live in `plugins/`; product and release decisions belong in `docs/`. Native `android/` and `ios/` folders are generated and ignored.

## Build, Test, and Development Commands

- `npm install` installs pinned dependencies; Node.js 22.13+ is required.
- `npm run android` builds and launches the Android development client.
- `npm start` starts Metro for an installed development client.
- `npm run typecheck` runs strict TypeScript validation.
- `npm test` runs `node:test` suites through `tsx`.
- `npm run prebuild` regenerates native projects and backup rules.
- `npm run build:preview` and `npm run build:production` request EAS APK/AAB builds.

## Coding Style & Naming Conventions

Use TypeScript, two-space indentation, single quotes, and semicolons. Components and types use PascalCase; functions and variables use camelCase; SQLite columns use `snake_case`. Keep monetary values as integer cents (`totalCents`) and dates as ISO strings. Preserve strict typing and avoid `any` outside database row boundaries. No formatter is configured, so match nearby code.

## Testing Guidelines

Use `node:test` and `node:assert/strict`; name files `*.test.ts`. Test quota, totals, payments, backup compatibility, and parsing as pure domain behavior. Run `npm run typecheck && npm test` before a pull request. There is no numeric coverage threshold, but each business-rule fix needs a regression test.

## Commit & Pull Request Guidelines

History favors short Conventional Commit subjects such as `feat: add encrypted backups`. Keep commits scoped. Pull requests should explain user-visible and offline-data effects, link issues or ADRs, include Android screenshots for UI changes, and report commands/devices tested. Never commit credentials, generated native folders, signing files, or real customer backups.
