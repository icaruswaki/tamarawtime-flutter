# Tamaraw Time — Codex Transit Integration Kit

**Created November 8, 2026.** This is an integration scaffold for an EXISTING Flutter project, not a standalone app. **Not yet integrated or end-to-end tested** with your private Tamaraw Time source.

## Contents
- `assets/transit/ltfrb_fares_2026_09_28.json` — Sep 28 2026 fare-reference parameters and provenance
- `lib/transit/fare_calculator.dart` — offline fare-estimation logic
- `lib/transit/transit_models.dart` — stop/route catalog models
- `lib/transit/transit_repository.dart` — Flutter asset loading
- `lib/transit/departure_calculator.dart` — pure automatic departure calculation
- `tools/import_gtfs.py` — import a **licensed/local** GTFS feed into compact JSON
- `assets/transit/transit_catalog.json` — intentionally empty starter catalog (not fake routes)
- `test/transit_calculators_test.dart` — initial tests
- `docs/FARE_SOURCES_AND_LIMITS.md` — fare evidence and important rounding caveats
- `docs/GTFS_LICENSE_AND_PROVENANCE.md` — source/licensing warnings
- `CODEX_PROMPT.md` — exact instructions to give Codex

## Use in existing Flutter project
1. Create a feature branch and back up your project.
2. Unzip this kit into a separate folder or copy its contents to a `codex_integration_kit/` folder **inside your existing project**. Do not overwrite `lib/`, `assets/`, or `test/` indiscriminately.
3. Give Codex `CODEX_PROMPT.md` and point it to the kit. Codex should inspect the existing app and carefully merge selected new files.
4. Under `flutter:` in `pubspec.yaml`, register `assets/transit/` (alongside existing assets). If using a different package name, change test package imports to match `pubspec.yaml`.
5. `flutter pub get`, `flutter analyze`, `flutter test` after integration.
6. For allowed historical GTFS data only: `python tools/import_gtfs.py --input PATH_TO_LICENSED_GTFS --output assets/transit/transit_catalog.json --max-routes 250`.

## What's NOT included
- No proprietary or copied Sakay GTFS route data
- No live jeepney routes, verified boarding stops, current train fare charts or schedules
- No real-time traffic or route-optimized trip planner
- No guaranteed free production tile or routing server
- No modifications to your actual Tamaraw Time repo (not provided)

## Developer note
`fare_calculator.dart` uses an **approximation**, not the official band-by-band paper matrix. For production, replace with verified per-distance fare bands and test against official fare guide PDF samples. Do not present the values as guaranteed ticket prices.
