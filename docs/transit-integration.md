# Transit kit integration

Integrated into the existing Flutter application on branch
`feature/gtfs-fares-2026`. The original four kit documents are retained under
[`transit-kit/`](transit-kit/README.md); they describe the supplied scaffold.
This guide describes the implementation in this application.

This is the V1 baseline guide. The [V2 rail/jeepney extension](rail-jeepney-v2.md)
adds a separate Sakay historical asset and directories; its import/provenance
notes supersede V1's empty-dataset description for that new directory. The
original generic catalog and all V1 fare safeguards remain unchanged.

## Existing application and data

The dashboard, expanded route map, green-and-gold logo, OSM tiles/routing,
foreground GPS, weekly classes, Supabase authentication and storage remain in
place. No database migration, remote deployment, catalog download, private key,
new application or existing-data rewrite is part of this integration.

`Planner` owns an asset-backed `TransitRepository`. It caches fare rules,
current service classifications and the optional historical catalog separately.
Home and Commute show the same `FareEstimator` view. Student pricing is an
explicit **Apply 20% student discount** choice for the current session, shared
between screens and reset at logout. It is not inferred from being an app user
and does not create a student-eligibility record in the research database.

## Fare reference and accuracy

`assets/transit/ltfrb_fares_2026_09_28.json` retains the kit's parameters:

| Category | Base fare | Base distance | Additional/km |
| --- | ---: | ---: | ---: |
| Traditional jeepney | PHP 14.00 | 4 km | PHP 2.00 |
| Modern jeepney | PHP 17.00 | 4 km | PHP 2.40 |
| Ordinary city bus | PHP 15.00 | 5 km | PHP 2.49 |
| Air-conditioned city bus | PHP 18.00 | 5 km | PHP 2.98 |

The September 28, 2026 reference rates were corroborated against the
[PTV report](https://ptvnews.ph/ltfrb-releases-new-matrices-for-puv-fare-hikes-effective-sept-28/).
The [official LTFRB fare page](https://ltfrb.gov.ph/fare-rates/) returned HTTP 403
during integration; official distance-band PDFs were **not verified**. These are
dated **reference estimates**, not certified fare-matrix or ticket prices.
Check for later orders and obtain the official posted matrix before production.

The pure calculator uses `base + max(0, traveledKm - baseKm) * additionalPerKm`,
then rounds to the nearest PHP 0.25. Student estimates multiply the **unrounded**
reference amount by 0.80 before the same illustrative rounding, preserving the
kit's behavior (PHP 14 regular → PHP 11.25 estimated student fare). Rounded
estimates are not a guarantee of the exact legal discount or operator charge.
Zero, negative, non-finite distances and unknown categories return unavailable.
Invalid rule values are rejected. The reference is not applied before its
effective date in Philippine time.

Student eligibility and identification follow
[RA 11314](https://elibrary.judiciary.gov.ph/thebookshelf/showdocs/2/88836).
Its official search excerpt corroborated the 20% regular-fare discount and
identification requirement; direct access to that page and the supplied Senate
page returned HTTP 403. Consult the complete Act, implementing rules and posted
operator matrix. Other discount categories are not inferred.

MRT/LRT, UV Express, P2P, provincial buses, EDSA Busway station fares,
taxi/TNVS and other modes require their own verified fare datasets. A provider
quote is shown separately, verbatim, and never receives a blanket student
discount through this calculator.

## Connecting verified travel distances and modes

Google Routes supplies `distanceMeters` on each transit step. The parser now
retains line `uri` and agency `uri` identities from `transitLine`; the existing
server field mask already includes those details. `BUS`, route names and a
user's preferred mode do **not** establish ordinary/air-conditioned city
service or traditional/modern jeepney classification.

`assets/transit/verified_fare_services.json` therefore ships **empty**. A
maintainer must independently verify current services before adding entries:

```json
{
  "services": [{
    "status": "verified_current",
    "line_uri": "https://OPERATOR/EXACT_PROVIDER_LINE_URI",
    "agency_uri": "https://OPERATOR/EXACT_PROVIDER_AGENCY_URI",
    "provider_vehicle": "BUS",
    "fare_mode": "ordinary_city_bus",
    "evidence_url": "https://AUTHORITY/CURRENT_SERVICE_CLASSIFICATION",
    "verified_at": "2026-11-08T00:00:00Z",
    "valid_until": "2026-12-08T00:00:00Z"
  }]
}
```

This is a **schema illustration**, not a real service record. Replace all fields
with verified evidence and appropriate validity dates. Allowed `fare_mode`
values are `traditional_jeepney`, `modern_jeepney`, `ordinary_city_bus`, and
`aircon_city_bus`. Verification timestamps require an explicit time zone and
must remain valid at the ride departure. City-bus rules accept provider `BUS`
only; jeepney classifications accept `BUS`, `OTHER` or `SHARE_TAXI` only with
the same independent verification. Rail/intercity/ferry types cannot authorize
these rules. Classification must apply to the actual service, including
its fare regime: do not map mixed vehicle classes, EDSA station-priced service,
UV/P2P or provincial service to a city-bus rule. If provider identities do not
uniquely distinguish the actual service class, leave it unavailable until a
better authorized provider or independently verified identifier is available.

Each fare requires all of:

- A fresh current provider itinerary (five-minute validity, no missed boarding).
- A matching, unexpired independent service verification; duplicate matches
  fail closed. A historical status cannot authorize a service.
- The actual provider vehicle type and exact line/agency identities.
- A positive finite **traveled distance on that individual transit ride**.

No GPS straight-line calculation, total-trip distance, polyline length, road
driving substitute, historic stop distance or guessed category is used. Each
transfer incurs its own base fare. Walking connectors are excluded. If only
some rides can be priced, the view explicitly shows an **incomplete subtotal**
and unavailable other rides, never a complete trip total. With the shipped empty
registry, LTFRB trip fares remain unavailable; existing provider quotes can
still be shown without modification. Positive flows are covered by synthetic
verified fixtures, not claimed as verified Metro Manila service coverage.

## Departure guidance

The kit's pure `calculateDeparture` helper is used by `DepartureAdvice`:

`leaveAt = classStart - providerTravelDuration - arrivalBuffer`

`prepareAt = leaveAt - preparationDuration`

Existing current itinerary freshness, actual arrival times, earlier scheduled
boarding constraints and late-state handling are retained. The dashboard and
commute route sheet show the class-specific recommendation. A manually changed
destination does not inherit the class's arrival target. Missing/stale ETA,
missing transit arrival data or invalid durations produce **ETA unavailable**.
Historical GTFS cannot enter this calculation. The existing optional manual
timing fallback stays separately labeled; the default stored 55-minute setting
is never substituted as a live provider ETA.

## Optional historical exploration and licensing

The catalog deliberately contains no routes or stops. Commute has a collapsed
**Historical transit reference** section; imported route names and ordered stops
are always labeled **HISTORICAL / UNVERIFIED**. It offers search and read-only
stop sequences, with no route recommendation, boarding action, fare or ETA.
The parser rejects live-status catalogs and invalid stop references/positions;
a route's imported flag cannot promote it to current service.

No Sakay feed or fare data is redistributed. The kit's provenance document
identifies the historical feed's DOTC Developer License Agreement; confirm its
terms and obtain any required permissions before importing or distributing.
Importer output does not confer redistribution rights. Keep publisher/version
and license/permission references with the imported catalog.

Run against a **local GTFS directory whose use is permitted**:

```powershell
python tools/import_gtfs.py --input PATH_TO_LICENSED_GTFS --output assets/transit/transit_catalog.json --max-routes 250 --source "Publisher and feed version" --license-reference "License URL or permission reference"
```

The importer uses Python's standard library, performs no network access, reads
BOM/CSV quoting, and sorts the first trip's valid stop sequence per route
without concatenating trips. It filters invalid coordinates and stop references,
omits service times and fares, and always marks output unverified historical.
This single-trip sample is not a complete set of operating route variants.
Assets are bundled at build time; rebuild after an approved catalog update.

## Checks and remaining data requirements

Executed for this integration:

- Dart formatting and `flutter pub get`: completed; no new dependencies.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: all **70 tests passed**, including existing account,
  schedule, responsive and expanded-map tests, plus fare, departure, parser and
  historical exploration cases.
- `node --test test/routes_backend.test.mjs`: all **8 tests passed**.
- Python importer tests: all **4 tests passed**, using synthetic local CSV data.
- Web release compilation: successful with the registered transit assets.

No Android/iOS build was rerun for this integration. Earlier mobility-build
results in the separate guide describe that earlier revision.

```powershell
dart format lib/transit lib/src/journey.dart lib/src/planner.dart lib/src/punctuality_overview.dart lib/src/commute.dart test/transit_calculators_test.dart test/transit_widgets_test.dart test/support/transit_fixture.dart test/journey_test.dart
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
node --test test/routes_backend.test.mjs
python -B -m unittest discover -s tools -p test_import_gtfs.py -v
```

On this workstation the registered system Python pointed to a missing executable;
Python 3.13 was installed through `uv python install 3.13`. It can be located with
`uv python find --managed-python 3.13` and invoked directly, or use a working
system Python with the commands above.

Real current multi-leg coverage still requires an authorized provider with
current service identifiers, verified boarding/alighting points, per-ride
traveled distances, service classifications and current timetables. Real-time
ETAs require an actual real-time source; static GTFS is insufficient. The
existing Google Maps/Routes credentials, protected Edge function and quota setup
are described in [the mobility guide](mobility-upgrade.md); this work does not
deploy them or establish live coverage. Official distance-band fare matrices and
any feed redistribution permissions remain data requirements. No physical-device
GPS, live Google API, new Supabase deployment or iOS validation is claimed.
