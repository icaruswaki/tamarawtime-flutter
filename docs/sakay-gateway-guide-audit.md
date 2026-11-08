# Sakay Gateway and Commute Guide audit — November 8, 2026

Both ZIPs were inspected before project changes. Their contents were treated as
reference material, not instructions to execute. No legacy application was run.

## Why the public-transit estimate is unavailable

Tamaraw Time already contains an OTP 2.8.1 Docker configuration, a validating
Python gateway, the `planConnection` GraphQL query, and a Dart OTP adapter.
`OtpJourneyProvider.fromEnvironment()` enables the adapter only when Flutter is
compiled with `OTP_PLANNER_URL`. Without the define it returns the displayed
"A current transit routing provider is not configured" reason. The usual shell
environment variable alone is insufficient for `String.fromEnvironment`.

There is also no running provider to connect: Docker is absent, the routing data
manifest has no feeds or OSM input, and no graph has been built. The user confirmed
they have no additional current GTFS feed or existing OTP service. Supplying a
URL or suppressing the message cannot fix these missing dependencies.

The existing gateway rejects unvalidated graphs, expired calendars, departed
journeys and trips outside their original service calendars. Flutter retains
walking/driving independently. No missing transit duration is replaced by OSRM.

## Sakay Gateway source findings

Source archive: `C:\Users\huaki\Downloads\sakay-gateway-master.zip`.
Reference repository: <https://github.com/sakayph/sakay-gateway>.

| File inspected | Useful architectural idea / legacy limitation |
| --- | --- |
| `README.md` | Explicitly an SMS frontend using a separate OTP server; it does not contain a routing graph or schedules. |
| `app/ws/OpenTripPlanner.scala` | Central planner client with origin/destination and timeout. It uses legacy REST paths, the current date but a fixed 11:59am time, and a transfer penalty. None of those endpoints or fixed-time behavior was copied. |
| `app/sms/RouteHandler.scala` | Reads the first `plan.itineraries` result and formats ordered legs. WALK becomes a walk instruction; rides name the line and destination. Stops come from `leg.from`/`leg.to`; rail fare lookup uses their stop IDs. Transfers follow successive ride legs. It filters some short legs using an old duration threshold; Flutter preserves access, transfers and egress instead. Google geocoding is not reused. |
| `app/models/Fare.scala` | Separates fare calculation from route acquisition. Bus/jeep tables index rounded-up kilometers; rail tables use ordered stop indices and hardcoded legacy route IDs. These historical prices and IDs are unsuitable for current fares and were not imported. |
| `conf/application.conf` | Separates the OTP URL from application logic and includes a local override. Its endpoint, secrets, and Google configuration were not copied; configuration values were redacted during inspection. |
| `LICENSE` | MIT, copyright 2013 Thomas Dy. Used as architectural reference; no Scala source was incorporated. |

## Commute Guide findings and licensing

Source archive: `C:\Users\huaki\Downloads\commute-guide-master.zip`.
Reference repository: <https://github.com/sakayph/commute-guide>.
Inspected README, full LICENSE, HTML guide text and archive inventory (including
the PDF, illustrations and styling assets).

The guide organizes explanations by mode: walking, jeepney, MRT/LRT, bus,
tricycle, UV Express, taxi and Comet e-jeep. Topics potentially useful to students
include recognizing route signs, identifying the intended alighting stop,
ticket/payment steps, boarding etiquette, finding station exits and walking
safely. Its old prices, card procedures and operating claims are not evidence
of November 2026 service. It contains no GTFS tables, routing backend or API.

The LICENSE specifies Creative Commons BY-NC-SA 4.0. The README uses an older
3.0 badge image; that does not replace the supplied 4.0 license. The guide credits
Veron Oliva, Philip Cheang, Rodrick Tan, Inna Tan, Pepe Bawagan and Patsy Lascano.
No guide prose, PDF or illustrations were copied into Flutter. Any future guide
adaptation must retain attribution, identify changes, and honor the
noncommercial/share-alike terms. The existing journey timeline uses original
UI text and itinerary data, not a republished guide.

## Existing GTFS inspected again

Read `C:\Users\huaki\Downloads\gtfs-master.zip` without modifying it:

| Table | Records |
| --- | ---: |
| routes | 1,717 |
| stops | 4,858 |
| trips | 1,864 |
| stop_times | 79,414 |
| calendar | 20 |
| calendar_dates | 0 |

Source calendar span: **2013-06-17 through 2020-06-30**. November 8, 2026
eligibility validation rejects it with "No usable current scheduled trips".
Its SHA-256 was unchanged before/after inspection.

The archive's rail names include LRT 1 / Baclaran–Roosevelt, LRT 2 /
Recto–Santolan, MRT-3 / Taft Ave–North Ave, and PNR MC / Metro Commuter.
These are historical feed records, not declarations of current routes. No dates,
stops, route extensions or frequencies were synthesized. Historical material
remains separate from `backend/otp/data` and the active routing graph.

The existing rail reference catalog, overlays and reviewed-point workflow are
preserved. Its names/interchange references cannot substitute for current GTFS,
walking access geometry or a connected graph; see the earlier
[station/geometry audit](sakay-otp-integration.md).

## Changes made in this pass

- `backend/otp/server.py`, `compose.yaml`: rail-only default, optional explicit
  road-transit enablement, and returned-mode filtering. Calendar validation is
  still mandatory. Departure searches use a 60-second response-delivery lead so
  initial walking legs do not immediately fail the departed-journey checks;
  actual OTP duration/departure/arrival remain unchanged. No historical fare
  constants were imported.
- `backend/otp/dev.ps1`: requires Linux containers; Smoke now fails when no
  validated connected rail itinerary is returned. Sample coordinates can be
  overridden, and the test checks actual returned legs and timing fields.
- `backend/otp/flutter.local.example.json`, `README.md`: reproducible local
  compile-time endpoint configuration, exact startup/validation commands and
  honest readiness requirements.
- `backend/otp/test_backend.py`: tests rail default, road-mode enablement,
  returned-mode filtering and the inability to bypass calendar checks.
- `test/otp_journey_test.dart`: synthetic OTP response through the Dart client,
  service and shared controller into the actual Commute Planner screen, including
  boarding, rail transfer, estimated arrival, class departure advice, and
  independent walking/driving alternatives. This is not a live journey test.

No authentication, student storage, class calendar, GPS, logo, map implementation,
OSRM parser, driving allowance, or LTFRB fare calculator was changed in this pass.

## Runtime acceptance status

| Required check | Actual result |
| --- | --- |
| Can OTP actually start? | **Blocked:** `dev.ps1 -Action Start` fails because Docker CLI/Desktop is absent. No OTP container was started. |
| Does supplied GTFS have current service? | **No:** last service date is June 30, 2020; validator rejects it. |
| Has OSM been loaded into OTP? | **No:** verified Geofabrik's current download metadata (613,252,038 bytes, last-modified November 8, 2026); transfer was too slow to complete, stopped, and the partial file removed. No complete PBF or graph remains. |
| Did a real routing server return a connected itinerary? | **No.** Neither archive supplies the missing live backend/data. |
| Can Flutter parse/display an OTP-shaped response? | **Yes, synthetic contract/widget tests**, including the actual Commute Planner and departure card. |
| Are live transit ETA/arrival/departure verified? | **No.** Only synthetic scheduled times have been tested; missing real times remain unavailable. |

Executed checks for this pass:

- `flutter analyze`: passed, no issues.
- `flutter test`: **94 tests passed**, including account, calendar, responsive
  UI, rail/fare, OSRM independence and the actual Commute Planner widget test.
- `flutter build web`: passed; output in `build/web` (Wasm dry run also passed).
- Python gateway/calendar/HTTP contract suite: **10 tests passed**. Its upstream
  is synthetic; this does not demonstrate a running OTP engine.
- PowerShell script syntax validation and `git diff --check`: passed.
- Real archived GTFS eligibility: correctly rejected, source archive unchanged.
- Real Docker startup attempt: failed because Docker is not installed.

The retained release and endpoint were checked against the official
[OTP 2.8.1 release](https://github.com/opentripplanner/OpenTripPlanner/releases/tag/v2.8.1)
and [pinned API documentation](https://github.com/opentripplanner/OpenTripPlanner/blob/v2.8.1/doc/user/apis/GTFS-GraphQL-API.md).
This is configuration/API verification, not proof of an installed or running
release. The existing query had already been validated against its pinned SDL.

## Remaining inputs

1. Docker Desktop running Linux containers.
2. Permitted, current operator GTFS for **LRT-1, LRT-2 and MRT-3**, including
   routes, accurate stops, trips, explicit stop times or appropriately supported
   frequency data, active service calendars/exceptions and directions/headsigns.
   Review feed coverage and provenance, not just its nominal end date.
3. A complete OSM PBF covering Metro Manila and the selected campus/rail access
   area, with sufficient margin for transfers and walking. The
   [Geofabrik Philippines source](https://download.geofabrik.de/asia/philippines.html)
   was verified but not fully downloaded.
4. Reviewed transfer/pathway/access data and a successful OTP graph build and
   connected-journey test. Current fare sources/classifications are required
   before assigning unsupported ride fares. Bus/jeepney expansion requires its
   own validated current service data.

A search found a [commercial corrected-feed listing](https://busmaps.com/fil/philippines/LTFRB-Philippines/metro-manila)
claiming 2026–2027 coverage, but it requires a data request and does not establish
operator-verified schedules or licensing for this project. It was not purchased,
downloaded, imported, or treated as current service. No third party was contacted.
