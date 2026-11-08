# Rail and historical jeepney integration V2

Implemented on `feature/rail-jeepney-v2`, extending the existing
`feature/gtfs-fares-2026` working code. The V1 changes, assets and tests were
preserved. The kit's prompt, README and source notes are retained in
[`transit-v2-kit/`](transit-v2-kit/README.md). These are supplied reference
instructions; this guide describes the resulting implementation.

## Using the directory

Open **Commute → Stations & routes**. Search and choose:

- **Rail stations**: all 51 stations, numbered in reference order, with a line
  filter and explicit beginning/ending terminals. Tap a station for its details.
- **Rail terminals**: the six endpoint stations. A station called *Central
  Terminal* is correctly treated as an intermediate LRT-1 station.
- **Rail transfers**: the three pedestrian connections, available from either
  station's detail. No walking time, path or accessible entrance is assumed.
- **Historical routes**: names, IDs, sample endpoint names and stop names are
  searchable; filter jeepney, unclassified road transit or historical rail.
- **Historical stops**: search the named stops occurring in the imported sample
  trips. Tap to see historical sample routes that include that stop.

Results are paginated in groups of 25, with **Show more**; search covers the full
catalog rather than only the visible page. Sample stop details link back to
routes. Potential first/last stops are **not confirmed physical terminals** and
all imported boarding/alighting locations remain unverified. License and
attribution are available within the historical directory.

## Rail reference

| Line | Stations | Beginning in supplied order | Ending in supplied order |
| --- | ---: | --- | --- |
| LRT-1 | 25 | Fernando Poe Jr. | Dr. Santos |
| LRT-2 | 13 | Recto | Antipolo |
| MRT-3 | 13 | North Avenue | Taft Avenue |

The interchanges are Doroteo Jose ↔ Recto, EDSA ↔ Taft Avenue, and
Araneta Center-Cubao ↔ Araneta-Cubao. Each represents separate stations connected
by a walking interchange, not a through-train service or a timed connection.

Data originates in the V2 kit's `rail_network_2026.json`. Station counts,
extension/endpoints and order were cross-checked against
[LRTA railway operations](https://www.lrta.gov.ph/railway-operations/),
[the government-hosted LRT-1 matrix station headings](https://ppp.gov.ph/wp-content/uploads/2014/08/LRT1_2025-Fare-Matrix-16.25_SJT.pdf),
and [MRT-3's station directory](https://www.mrt3.com/index.php/menu-stations).
The DOTr MRT-3 about page timed out, although its search excerpt corroborated
the 13-station corridor. The government-hosted matrix was consulted for station
headings only: **no train fare values were imported or calculated**.

The bundled network is a **station reference**, not evidence of current service,
opening hours or train availability. It does not contain headways, departure
times, arrival predictions, train fares or ride durations.

## Historical Sakay import and provenance

The attached `gtfs-master.zip` was imported locally after reviewing both its
`LICENSE.md` and the upstream [DOTC developer terms](https://github.com/sakayph/gtfs/blob/master/LICENSE.md).
The user requested this import after license review. The importer was run with
its explicit acknowledgement flag. The full supplied terms are bundled as
`assets/transit/sakay_gtfs_LICENSE.md` and shown by the app.

The terms limit use to assisting transit riders or promoting public transport,
restrict data uses/transfers, disclaim accuracy and prohibit implied endorsement.
This is not an unrestricted software/data license. Retain the terms and
attribution with this derived historical dataset, review continued compliance
and any applicable permissions before public distribution, and do not sell the
data separately. No DOTC or Sakay logos/endorsement claims were added.

Data provided by the Department of Transportation and Communications;
historical feed adapted by Sakay.ph. Upstream:
[sakayph/gtfs](https://github.com/sakayph/gtfs).

Source archive SHA-256:
`064750979de1635c16c1298f5410a78034b9de8f502ad0ff9f7043304b3b06fa`.
The feed metadata names Sakay.ph but supplies no feed version or validation date;
no current operating date can be inferred.

Imported into `assets/transit/sakay_historical.json`:

| Historical classification | Routes |
| --- | ---: |
| Jeepney reference | 1,522 |
| Road transit, unclassified | 191 |
| Rail reference | 4 |
| Total | 1,717 |

There are **4,857 distinct named stops in the sampled trip sequences**. These
are not asserted to be an exhaustive current stop network. Only obvious PUJ or
jeepney names receive the jeepney reference classification. GTFS `route_type=3`
alone does not prove jeepney/bus/UV class, modern/traditional equipment or a fare
regime. Older rail entries, such as Baclaran–Roosevelt and Recto–Santolan, remain
historical and never replace the separate 51-station directory.

The provided importer was hardened to handle BOMs, nested ZIPs, invalid sequence
values, non-finite/out-of-range coordinates and duplicate ZIP file ambiguity.
It retains stop names when coordinates are missing, includes archive provenance,
omits scheduled stop times/fares, and marks every route historical and not
validated as operating. It preserves the first sample trip's sequence, not every
direction/variant. Historical coordinates never automatically become reviewed
map locations.

To reduce repeated stop records, CLI output uses normalized schema version 2:
a shared named-stop dictionary and per-route ordered stop ID/sequence visits.
The result is approximately 4.13 MB, down from the kit-format 13.0 MB, without
dropping routes or sample visits. The Flutter reader accepts both the original
schema 1 and normalized schema 2. The importer function `convert` retains its
original schema-1 result for compatibility.

Reproduce the import with a working Python 3 interpreter:

```powershell
python -B tools/import_sakay_gtfs.py --input "C:\Users\huaki\Downloads\gtfs-master.zip" --output assets/transit/sakay_historical.json --accept-license
```

The workstation's managed interpreter is
`C:\Users\huaki\AppData\Roaming\uv\python\cpython-3.13-windows-x86_64-none\python.exe`.
Raw GTFS files were not extracted into the application. No private Sakay API,
scraping, paid API or remote publishing is involved.

## Coordinates, maps, GPS and walking

The kit deliberately supplies **no rail coordinates**. Historical GTFS locations
are retained as unreviewed source data and are not plotted or used for proximity
or walking directions. Public coordinate-review attempts failed (Overpass HTTP
406 and alternate endpoint timeout); no inferred replacements were entered.

`assets/transit/reviewed_transit_points.json` therefore ships empty. Once a
maintainer reviews a licensed geographic source, add a point keyed by the exact
rail station ID (for example `LRT-1:Doroteo Jose`) or `sakay:<stop_id>`, containing:

- `latitude` and `longitude`: actual finite geographic coordinates.
- `source_url`: HTTPS evidence for the named location.
- `reviewed_on`: the date of that review.

The directory then displays an OSM marker and attribution, source and review
date, plus **Plan a walk to this location**. These are location references, not
verified platform entrances, accessible paths or evidence that a jeepney runs.
The existing commute controller receives that destination in **Walking** mode,
retaining the user's existing origin/GPS workflow. Actual walking directions,
distance and duration are requested through the existing routing provider.
Permission requests remain user-controlled. No historical shape or synthetic
point-to-point transit line is drawn. No coordinate history is stored in
Supabase. Positive map/walking behavior was tested with synthetic reviewed
fixtures; no real catalog point is claimed reviewed or mapped in this version.

## Current service backend and fares

`OperatingRouteSource` is an injectable backend contract. The default source
returns no evidence and makes no network requests. A future authorized adapter
must supply an independent route ID, HTTPS evidence, UTC validation/expiry times,
current operating status and boarding/alighting verification. Missing, stale,
historical, wrong-route or failed lookup responses fail closed. A separately
validated record can be displayed beside a sample; it never changes the sample's
historical provenance or becomes an ETA.

This is an interface and validation layer, **not a deployed operating-route
database or a claim of verified jeepney coverage**. Live multi-leg guidance still
needs an authorized current provider, verified physical boarding/alighting
points, actual per-ride distances and service classes, and actual timetable or
real-time data as appropriate.

The September 28, 2026 LTFRB JSON, calculator, opt-in student discount and
verified-fare service registry are unchanged. Historical road routes do not feed
that registry or the existing `JourneyController`. Train fares remain unavailable
until a separate verified fare source is integrated. Current provider estimates
and punctuality guidance continue through the existing shared route state;
historical stop times never enter an ETA or departure calculation.

Supabase authentication, student schedules/data, green-and-gold logo, existing
OSM map/GPS and the V1 generic historical explorer remain intact. No database
migrations, authentication changes, remote deployments or new API keys were added.

## Validation commands

Executed on this workstation:

- Formatting and `flutter pub get`: completed, with no dependency changes.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: **82 tests passed**, preserving the previous 70 tests
  and adding ordered station/terminal/transfer checks, actual import parsing,
  evidence validation, historical search/detail, responsive directory and
  reviewed-location walking handoff tests.
- `node --test test/routes_backend.test.mjs`: **8 tests passed**.
- Python importer suites: **11 tests passed**, including the original importer.
- `flutter build web --no-pub --no-wasm-dry-run`: successful, including the
  rail catalog, compact historical catalog and source license assets.

Map behavior is exercised with synthetic coordinates; the shipped reviewed-point
registry remains empty. Android/iOS builds were not rerun for this extension.

```powershell
dart format lib/transit lib/src/commute.dart test/rail_jeepney_test.dart test/transit_directory_test.dart
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
node --test test/routes_backend.test.mjs
python -B -m unittest discover -s tools -p "test_import*.py" -v
flutter build web --no-pub --no-wasm-dry-run
```

No physical-device GPS, real operating transit services, train arrival source,
new backend deployment, or current boarding-platform verification is claimed.
