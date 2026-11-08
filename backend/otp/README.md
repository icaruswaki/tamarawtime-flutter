# Local scheduled-transit routing for Tamaraw Time

Status on November 8, 2026: configuration and client integration are implemented;
**no real OTP graph has been built and no current Manila itinerary has been
returned**. Docker is not installed on the inspected workstation. Its system
Java is 8, while this OTP release requires Java 21. Docker supplies its own JVM.
The supplied Sakay GTFS service dates end June 30, 2020. They are not rewritten.

This extends the existing application. OSRM walking/driving, the secondary
driving allowance, the rail/historical directories, logo, authentication,
Supabase records, class schedules and fare calculator remain in place.

## Architecture

Flutter `JourneyService` retains its authenticated Google Routes integration.
If that cannot return transit options, an opt-in `OtpJourneyProvider` posts the
existing journey query to this gateway. Walking and driving continue through
their existing provider paths and publish independently through the shared
controller. No transit time is inferred from a driving time.

The gateway sends `plan.graphql` to OTP **2.8.1**, pinned for a reproducible
schema contract. It uses the supported GTFS GraphQL endpoint `/otp/gtfs/v1`
and `planConnection`; the deprecated `plan` query and removed REST API are not
used. Inputs use coordinate objects and exactly one of `earliestDeparture` or
`latestArrival`. Walking access, egress and transfers are enabled; every
returned candidate must include transit.

OTP computes paths, timetable waits and transfers from GTFS and OSM. The
gateway checks graph/input hashes, provenance review expiry, and **each returned
trip's original service calendar**, including calendar exceptions and service
days past midnight. It rejects stale/mismatched data, missed departures and
connections arriving after an arrival target. The app retains provider total
duration, including waiting, rather than summing only movement durations.

GTFS data is a schedule, not a real-time arrival source. No GTFS-RT updater is
configured. The app labels OTP results accordingly. No fare is inferred from a
route name, generic BUS type or old Sakay fare. Existing independent verified
fare classifications and per-ride distances can support the existing fare
calculator; otherwise a fare stays unavailable. GTFS Fares v2 ticket selection
is not implemented in this adapter. BUS alone does not establish jeepney,
modern/traditional vehicle type, UV Express or fare regime.

## Required inputs

Obtain permitted, operator-maintained **current Metro Manila** GTFS. It needs
agency, routes, stops, trips, stop_times and calendar/calendar_dates, current
directions/headsigns, and sufficiently accurate boarding/alighting coordinates.
Shapes improve ride geometry; transfers/pathways improve interchanges and
station access. Current rail, bus and jeepney coverage require corresponding
current datasets; a feed for one mode cannot establish the others.

Also obtain an OSM PBF covering the entire service/walking area. The
[Geofabrik Philippines extract](https://download.geofabrik.de/asia/philippines.html)
is a possible licensed source; inspect its timestamp and crop a suitable area
with sufficient walking/network margin before building. No complete PBF is
available locally. A November 8 download attempt was stopped due to slow transfer;
the partial file was removed. No OSM geometry was invented. OSM routing data
does not establish train operating times.

The eligibility validator is deliberately conservative: it requires explicit,
chronological stop times and Asia/Manila agency time zones. It is **not** a full
GTFS or PBF validator, does not verify publisher claims or geographic coverage,
and does not replace an operator review, the MobilityData GTFS validator, or
OTP's build reports. Its PBF preflight only checks provenance/file presence;
the real OTP build must successfully parse and link the actual PBF. Synthetic
tests use sentinel PBF/graph bytes solely to exercise gateway contracts and
never represent a real OTP build.

Copy permitted files into `data/`, with GTFS filenames ending `.gtfs.zip` and
OSM filenames ending `.osm.pbf`. Fill `data/datasets.json` using this **schema
illustration**, replacing all placeholders with actual sources/review dates:

```json
{
  "feeds": [{
    "id": "operator_feed",
    "file": "operator-current.gtfs.zip",
    "source_url": "https://OPERATOR/CURRENT_FEED",
    "license_url": "https://OPERATOR/DATA_LICENSE",
    "verified_on": "YYYY-MM-DD",
    "valid_until": "YYYY-MM-DD"
  }],
  "osm": {
    "file": "metro-manila.osm.pbf",
    "source_url": "https://PUBLISHER/ACTUAL_EXTRACT",
    "license_url": "https://www.openstreetmap.org/copyright",
    "verified_on": "YYYY-MM-DD",
    "valid_until": "YYYY-MM-DD"
  }
}
```

`valid_until` is the review's freshness limit, **not an extension to a GTFS
calendar**. The validator intersects eligibility with actual source service
dates and never edits them. Files and generated graphs/manifests are ignored by
Git. The shipped manifest is empty; historical application assets are never
auto-imported into this routing directory. Keep licenses with any distributed
data. Do not rename the archived Sakay feed as "current" or extend its dates.

## Windows and Docker Desktop

Install and start Docker Desktop using Linux containers with Compose v2.
Allow sufficient Docker memory; the supplied JVM heap is 4 GiB and may need to
increase for a large extract. System Java/Python are not required for this
Docker workflow. From the existing application repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File backend/otp/dev.ps1 -Action Check
# Supply/review data as described above, then:
powershell -NoProfile -ExecutionPolicy Bypass -File backend/otp/dev.ps1 -Action Build
powershell -NoProfile -ExecutionPolicy Bypass -File backend/otp/dev.ps1 -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File backend/otp/dev.ps1 -Action Smoke
```

Build validates the supplied files, generates explicit feed IDs/OSM sources,
builds and saves the OTP graph, and seals hashes **only after success**. A graph
predating validation cannot be sealed. Start checks the sealed graph before
launching services. OTP startup can take time; rerun Smoke until healthy rather
than assuming `docker compose up` proves readiness. Health probes the actual
GraphQL server after checking data. A successful health result does not prove
that a particular origin/time has a connection. Smoke now **fails** for an empty
or unvalidated result and requires a positive-duration itinerary with transit
legs and departure/arrival timestamps. It tests a rail journey from a sample
Quezon City origin to FEU Tech. Override `-OriginLatitude`, `-OriginLongitude`,
`-DestinationLatitude` and `-DestinationLongitude` for a known covered journey.
No connection may be a legitimate routing result, but it is not a passed
end-to-end acceptance test. Inspect the returned steps in Flutter too.

OTP: `http://127.0.0.1:8080/graphiql` for API inspection.
Gateway health: `http://127.0.0.1:8090/health`.
Gateway plans: `POST http://127.0.0.1:8090/plan`.

Enable the adapter for a Flutter development run:

```powershell
flutter run -d chrome --web-port 5000 --dart-define=OTP_PLANNER_URL=http://127.0.0.1:8090/plan
# Equivalent checked-in, non-secret local configuration:
flutter run -d chrome --web-port 5000 --dart-define-from-file=backend/otp/flutter.local.example.json
```

Without this define the app makes no OTP request and explains the missing current
transit provider. For an Android emulator the adapter accepts `10.0.2.2` as a
local development host; platform cleartext/network policies still apply. Use a
proper HTTPS service for device/production deployment. Do not modify production
authentication or weaken platform networking merely to connect this local demo.

`OTP_PLANNER_URL` is a **Flutter compile-time define**. Setting an ordinary shell
environment variable alone does not configure the app. Rebuild/restart Flutter
after changing it. It points to our `/plan` gateway, not directly to OTP's
GraphQL endpoint. Defining it cannot create missing schedules or start OTP.

The gateway defaults to rail (`RAIL`, `SUBWAY`, `TRAM`) with walking access,
egress and transfers, to support LRT-1/LRT-2/MRT-3 first when current feeds arrive.
It filters returned transit legs to the requested modes too. After obtaining
and reviewing current bus/jeepney data, set `$env:OTP_ENABLE_ROAD_TRANSIT='true'`
before starting Compose to permit BUS legs. Enabling this flag never bypasses
the graph or per-trip calendar checks. GTFS BUS alone does not identify a
jeepney, UV Express service, or fare category; existing verified classification
and fare rules still apply. No historical Sakay fare tables are used.

For requests without a class arrival target, the gateway asks OTP for departure
at least 60 seconds ahead to allow query/response delivery. Otherwise an initial
walking leg starting exactly "now" can appear already departed when Flutter
receives it. This changes the requested search time only: the displayed duration,
departure and arrival still come from OTP. It is not the driving traffic
allowance. Arrival-target queries retain their requested latest arrival.

Stop local services:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File backend/otp/dev.ps1 -Action Stop
```

Ports bind to host loopback. Gateway CORS permits local development origins.
It logs no request bodies and persists no coordinates/student information.
This is **local development infrastructure**, not an authenticated public API.
Before any public deployment, provide HTTPS, authentication, rate limits and
controlled origins, and review data licensing. No external deployment occurred.

## Tests and actual limitations

```powershell
flutter analyze
flutter test
flutter build web
node --test test/routes_backend.test.mjs
python -B -m unittest discover -s backend/otp -p test_backend.py -v
python -B -m unittest discover -s tools -p "test_import*.py" -v
```

Use a working Python 3.13 interpreter; this workstation's `python` command is a
Windows Store stub. The managed interpreter used in verification is documented
in `docs/rail-jeepney-v2.md`.

The backend tests start a real local gateway and a **synthetic OTP HTTP stub**.
They test GraphQL request/response plumbing, current/expired calendars,
exceptions, hashes, missed departures, arrival targets and no-data behavior.
They do not assert real rail or road operations. The Dart/widget tests cover
multileg recommendations, waiting time, stops, transfers, egress, map decoding,
departure advice, source attribution and independent OSRM estimates.

The query's fields/arguments/types were checked against the official 2.8.1 SDL
using an isolated GraphQL validator. GraphQL Java's schema was loaded with
`assume_valid=True` because graphql-core rejects OTP's pre-existing interface
deprecation mismatch; query field/type validation still ran. This checks the
contract but does not replace running OTP. No Docker daemon/image/real graph was
available here; the local Check command reported missing Docker. No real current
transit itineraries were returned. See the detailed source/data audit in
`docs/sakay-otp-integration.md`.
The additional gateway/guide archive audit and latest acceptance results are in
`docs/sakay-gateway-guide-audit.md`.

## Primary API/configuration references

- [OTP 2.8.1 GTFS GraphQL API](https://docs.opentripplanner.org/en/v2.8.1/apis/GTFS-GraphQL-API/)
- [Pinned GraphQL schema](https://raw.githubusercontent.com/opentripplanner/OpenTripPlanner/v2.8.1/application/src/main/resources/org/opentripplanner/apis/gtfs/schema.graphqls)
- [Official container workflow](https://docs.opentripplanner.org/en/v2.8.1/Container-Image/)
- [Explicit feed IDs and OSM build inputs](https://docs.opentripplanner.org/en/v2.8.1/BuildConfiguration/)
- [Java requirements and basic setup](https://docs.opentripplanner.org/en/v2.8.1/Basic-Tutorial/)
