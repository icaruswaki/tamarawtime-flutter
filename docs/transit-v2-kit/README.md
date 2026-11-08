# Tamaraw Time — Sakay Historical GTFS + Rail Stations V2

This is an **integration kit**, not a completed route engine or verified live transit feed. It is designed to extend Codex's `feature/gtfs-fares-2026` work without losing existing schedules, Supabase data, fare calculators or UI.

## What's provided
- `data/rail_network_2026.json`: **51 stations** in LRT-1 (25), LRT-2 (13), MRT-3 (13), their order, and three pedestrian interchanges. Positions are intentionally `null`; don't invent coordinates.
- `tools/import_sakay_gtfs.py`: **working stdlib Python importer** for routes, named stops, and sample ordered stop sequences in Sakay.ph GTFS, with license acknowledgement. It labels all output historical.
- `flutter/rail_reference_repository.dart`: Flutter asset loader/models to feed a rail directory screen.
- `CODEX_PROMPT.md`: Integration task instructions.
- `docs/SOURCES_AND_LIMITATIONS.md`: provenance and restrictions.

## Getting Sakay.ph historical data yourself
1. Read the license: https://github.com/sakayph/gtfs/blob/master/LICENSE.md
2. Visit https://github.com/sakayph/gtfs and use **Code → Download ZIP**, or download files with Git. Do not assume the data is a current operating service.
3. From the `tamaraw_time` repository root, run one of the following, adjusting local paths:

```powershell
python tools/import_sakay_gtfs.py --input path/to/sakay-gtfs-master --output assets/transit/sakay_historical.json --accept-license
```

Or point `--input` to a `.zip` containing GTFS text files.

4. Copy `data/rail_network_2026.json` into your app at `assets/transit/rail_network_2026.json`.
5. Add `assets/transit/` to the Flutter `pubspec.yaml` assets list (merge with existing assets; do not replace them).
6. Have Codex integrate `flutter/rail_reference_repository.dart` with your existing models and build a browsable rail network, historical-only jeepney directory, station/terminal search, and transfers.

## Crucial restrictions
- No GTFS data copied or bundled in this ZIP. You must check source terms yourself.
- No train schedules, frequency, map coordinates, current service declarations, live stop arrivals, or train fares are fabricated here.
- Sample-trip ordered stops from historical GTFS are a **reference**, not a confirmed current boarding guide.
- Do not calculate current ETA from old scheduled stop times.
- `route_type=3` is shared across many road-transit classes; importer only tags obvious `PUJ` entries as jeepneys, and leaves others unclassified.
- Train lines need geocoded, reviewed station coordinates before map markers or proximity calculations work.
- Preserve existing September 2026 fare JSON/calculation from the user's app; rail fares require separate official provider rules.
