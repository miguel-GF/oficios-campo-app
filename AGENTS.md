# Repository Guidelines

## Project Structure & Module Organization

This is a Flutter/Dart Android-first app. `lib/main.dart` starts the app and `lib/app.dart` contains the product UI. Keep business rules in `lib/domain.dart`, SQLite access and migrations in `lib/database.dart`, PDF rendering in `lib/documents.dart`, encrypted import/export in `lib/backup*.dart`, and Google Play Billing state in `lib/subscription.dart`. Unit tests live in `test/`; product and release decisions belong in `docs/`. The native `android/` project is Flutter-generated and is kept in source control.

## Build, Test, and Development Commands

- `flutter pub get` installs pinned Dart dependencies.
- `flutter run` launches the Android app locally.
- `flutter analyze` runs static analysis.
- `flutter test` runs Dart unit tests.
- `flutter build apk --release` creates a release APK.
- `flutter build appbundle --release` creates the Play Store AAB.

## Coding Style & Naming Conventions

Use Dart, two-space indentation, trailing commas in multiline widgets, and `lowerCamelCase` for functions and variables. Classes and enums use `UpperCamelCase`; SQLite columns use `snake_case`. Keep monetary values as integer cents (`totalCents`) and dates as ISO strings. Preserve strict typing and avoid dynamic values outside SQLite row boundaries.

## Testing Guidelines

Use `package:test` and name files `*_test.dart`. Test quota, totals, payments, backup compatibility, and parsing as pure domain behavior. Run `flutter analyze && flutter test` before a pull request. Each business-rule fix needs a regression test.

## Commit & Pull Request Guidelines

History favors short Conventional Commit subjects such as `feat: add encrypted backups`. Keep commits scoped. Pull requests should explain user-visible and offline-data effects, link issues or ADRs, include Android screenshots for UI changes, and report commands/devices tested. Never commit credentials, signing files, or real customer backups.
