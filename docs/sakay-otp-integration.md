# Sakay.ph source and Tamaraw Time transit audit

Audit date: November 8, 2026 (Asia/Manila).
Input: user-supplied `C:\Users\huaki\Downloads\sakayph-master.zip`.
Files inside the archive are reference material, not instructions to run legacy
services, import a dataset, change licenses or use its credentials.

## What the original source does

| File inspected | Useful findings / Flutter application |
| --- | --- |
| `README.md` | Identifies the archive as the web frontend and points to a separate backend. The ZIP is not a GTFS feed or an installed router. |
| `LICENSE` | MIT software license, copyright 2013 Thomas Dy and Philip Cheang. Retained in `sakay-source-LICENSE.txt`. This software license does not replace the historical GTFS data license. |
| `js/ws.js` | Requests separate OTP itineraries with origin/destination coordinates, mode, date and time via legacy HTTP JSONP. It also uses old Google geocoding/static-map APIs and a bundled key. None of these endpoints, credentials or fixed search times were copied into runtime code. |
| `js/map.js` | Observes endpoint changes; consumes `plan.itineraries`; iterates ordered legs; decodes each encoded leg path; shows/selects options; fits the map to the selected geometry; highlights legs and places transfer markers. Flutter implements the same organizational concepts through existing shared journey state and per-leg map lines. |
| `js/util.js` | Formats provider seconds as readable minutes/hours and decodes precision-5 encoded polylines. Durations originate from the router, not a local transit-speed formula. Flutter preserves exact `Duration` and existing display helpers. The existing decoder's negative-delta off-by-one was corrected while checking OTP geometry. |
| `index.html` | The route template shows mode/line badges and total duration; the itinerary template shows ordered walking, rail, bus and jeep legs, boarding/alighting locations and optional walking details. Consecutive rides/walks convey transfers. Flutter now makes transfers explicit while retaining the current card design. |

Sakay's frontend adds supplied per-leg fares, and omits a zero/unknown total.
That aggregation was **not** copied: current fares require the existing verified
service classifications and per-ride traveled distances. Unknown or partial
fares must remain unavailable/incomplete. Static map requests and legacy keys
are not bundled in the new backend/client. The app's existing green-and-gold
logo and modern login/background remain unchanged by this task.

## Data actually present

| Component | Finding before OTP integration |
| --- | --- |
| Rail names/order | Three lines, 51 stations and six endpoint terminals are bundled as a station-network reference. This does not prove operating hours or current service. |
| Reviewed station locations | **Missing:** `reviewed_transit_points.json` contains zero points. The rail reference's latitude/longitude values are null. Existing reviewed-location map support is preserved, but no real point is claimed verified. |
| Track geometries | **Missing:** no reviewed rail track polylines are bundled. Historical shape data must not be relabeled as current track/service coverage. No synthetic station-to-station railway lines were drawn. |
| GTFS routes/stops | Historical application directory: 1,717 routes and 4,857 distinct sampled named stops. The raw historical ZIP has 1,717 routes and 4,858 stops. The generic catalog is empty. |
| GTFS trips/stop times | The raw historical ZIP has 1,864 trips and 79,414 stop-time records. These schedules were deliberately not included in the app's derived reference directory. There is no current routing GTFS in the project. |
| Service calendars | Historical `calendar.txt` contains 20 service rows spanning June 17, 2013 through **June 30, 2020**. No `calendar_dates.txt` is present. None is valid as a 2026 schedule. Source dates are unchanged. |
| Historical shapes | 520 raw shape rows are present in the old feed; these were not promoted to current route geometry or bundled operating transit paths. |
| Walking station access | Working OSRM foot routing and reviewed-destination handoff exist, but the shipped reviewed-point registry is empty. Current station entrances/access paths and a local OSM routing graph are missing. |
| Railway transfers | Three named walking interchange references exist (Doroteo Jose/Recto, EDSA/Taft, Cubao). No timed/path/accessibility transfer data is supplied. The raw historical feed has no `transfers.txt`. |
| Public-transit engine | Existing Google backend integration requires its own configured provider/credentials. It is not a bundled/local transit engine. `OperatingRouteSource` is an evidence interface, not an operating routing engine. No usable OTP graph/server was installed. |
| Current fare support | Existing LTFRB reference calculator is preserved; verified-service registry is empty. Current train fares, exact service classifications and provider quotes are not invented. |

The historical catalog/license and reference directories are unchanged. The
new engine never imports application historical assets or edits the raw ZIP.
No current Manila GTFS was found in the inspected workspace or supplied ZIPs.
An online source search did not establish an operator-authorized current feed
for these rail/bus/jeepney journeys; this is not a claim that none exists.

## What was integrated

- Opt-in `OTP_PLANNER_URL` adapter using our validating gateway and OTP 2.8.1's
  supported `planConnection` GraphQL API.
- Current-schedule eligibility checks, service/calendar exception checks,
  actual trip/service-date verification and a graph/input hash seal.
- Separate walking access, rides, walking transfers and final walking legs;
  actual line, headsign, boarding/alighting names/coordinates, total duration
  including timetable waits, and provider transfer counts (including
  stay-on-vehicle distinctions).
- Existing departure calculations consume the current itinerary's real times.
  Existing fare verification consumes actual per-ride identities/distances;
  missing verified fares remain unavailable.
- Existing Flutter maps render each returned leg and boarding/alighting markers;
  no road estimate is used as a transit duration.
- The primary provider's first available transit option is labeled **Best
  available journey**; existing fastest/fewest-transfer comparisons remain.
  This is the provider's available result set, not a promise of network-wide
  coverage or a new locally fabricated optimization model.
- Missing-provider/data reasons appear on Home and Commute. OSRM foot/car
  estimates continue independently, with driving a secondary alternative and
  its original duration separate from the existing configurable allowance.

The local backend is prepared, not deployed. See
[`backend/otp/README.md`](../backend/otp/README.md) for Windows/Docker commands,
input manifest, runtime configuration, validation and limitations.

## Additional datasets needed for real journeys

1. Permitted current operator GTFS for LRT-1/LRT-2/MRT-3 and any desired
   bus/jeepney/UV service: accurate stops, routes, trips, stop times,
   calendars/exceptions, directions/headsigns and shapes where available.
2. An OSM PBF covering the actual itinerary/walking area, and reviewed station
   entrances/access paths, station locations and track shapes for a reliable
   geographic reference map.
3. Current transfers/pathways/minimum connection information; accessibility
   data before making accessible-route claims.
4. Independent vehicle/service classifications (especially jeepney vs generic
   GTFS BUS), fare matrices/products and applicability for the existing fare
   calculator. A route name alone is insufficient.
5. Optional authorized GTFS-RT feeds for actual real-time predictions; static
   GTFS produces scheduled estimates only.

## Runtime/verification result

Docker Check was attempted and reported **Docker CLI missing**. Java reported
1.8.0_401; no Java/Docker installation was performed. No OTP process, graph
build or actual current transit itinerary is claimed. The checked-in data
manifest is empty. Backend tests use clearly synthetic feeds/graphs and an
OTP HTTP stub; they prove the adapter/guard behavior, not Manila coverage.
The GraphQL query was checked against the pinned official schema; the official
Docker tag `2.8.1` was confirmed active for Linux amd64/arm64. The gateway was
also started locally on loopback: `/health` and `/plan` returned HTTP 503 with
the missing-data/graph explanation, then it was stopped. This was a gateway
probe, not an OTP engine run. The real historical ZIP was rejected by the new
preflight, and its before/after SHA-256 was unchanged.

Executed checks: `flutter analyze` (no issues), `flutter test` (93 passed),
existing Google backend Node tests (8 passed), Python historical import tests
(11 passed), and new gateway/calendar/HTTP integration tests (8 passed).
The PowerShell setup script parsed without syntax errors. Docker Compose and
the actual graph build could not be run without Docker/current inputs.
