# Local rail journey planner

The primary transit request previously reached only the configured Google/OTP
providers. With no current provider, it returned an empty result; the railway
catalog was a reference directory, not a routing graph. `JourneyService` now
tries `LocalTransitProvider` after the remote transit providers. Walking and
driving still publish independently through `JourneyController`.

## What is implemented

- Dart uniform-cost (Dijkstra) search over directed, identified rail edges.
  Boarding/alighting restrictions, explicit interchanges, loop prevention,
  review validity and a transfer preference are enforced. Names/proximity
  never create transit connections.
- Up to three alternatives from a bounded candidate search: the three nearest
  eligible origin and destination stations within 1.8 km, each requiring an
  actual OSRM pedestrian route of at most 2.2 km. Interchange walks must be at
  most 1.2 km. Route endpoints must snap within 80 m of the mapped access point.
  These limits bound the MVP's coverage; this is not an exhaustive optimizer.
- Three topology-preferred paths per access/egress pair; candidates with complete
  reviewed timing rank by duration, then transfers and walking. Untimed routes
  rank after timed ones, by transfers and walking. Topology weights are never
  presented as minutes. Untimed alternatives that are worse on every known
  criterion (transfers, ride stops, walking) are omitted, rather than filling
  three cards with detours. Untimed routes never get a Fastest badge.
- Automatic Transit search, structured walking/boarding/direction/alighting/
  transfer instructions, map selection and step geometry. Mobile uses a map
  and draggable results sheet; desktop uses a left results sidebar and map.
- Reference tracks and tappable stations; selected walking legs use dotted
  paths, rail legs are highlighted, alternatives are faint gold. Each leg
  remains separate: missing track geometry is not bridged by straight lines.
- A replaceable `JourneyProvider` interface; the existing OTP GraphQL gateway
  and `OTP_PLANNER_URL` integration remain available.

## Source data and limits

The existing `rail_network_2026.json` supplies station identities/order and three
interchange pairs. The new OSM-derived graph and GeoJSON use connected nodes
on these actual directed route relations:

| Railway | Directed OSM relations |
| --- | --- |
| LRT-1 | [110418](https://www.openstreetmap.org/relation/110418), [8000260](https://www.openstreetmap.org/relation/8000260) |
| LRT-2 | [110410](https://www.openstreetmap.org/relation/110410), [8000264](https://www.openstreetmap.org/relation/8000264) |
| MRT-3 | [109159](https://www.openstreetmap.org/relation/109159), [8000253](https://www.openstreetmap.org/relation/8000253) |

`local_transit_graph.json` records relation versions/timestamps and the source
URL for every station/edge. The imported network contains **51 stations, 95
directed segments and six directed interchange references**. Only **24** stations
have mapped public ground-level entrances selected from their OSM stop areas;
the other 27 remain reference/pass-through stations and cannot be used to board
or alight. Emergency/service/exit-only and private entrances are excluded.
An absent northbound Taft stop position leaves one MRT-3 segment unsupported.
No invented node or geometry fills that gap.

The topology review window is 9 November–9 December 2026 (Manila). This is a
conservative application freshness policy, **not a service calendar** or a claim
of field verification. Routing stops accepting expired reviews until the data
is actually reviewed again; the reference overlay remains visible. Internal
station paths, platform access, accessibility, closures, opening hours and
service operation still need verification. An OSRM street route to an entrance
does not validate an internal station connection.

`tools/build_local_rail_graph.py` rebuilds the two derived files from OSM API
snapshots named `route-<relation>.json` and `area-<stop-area>.json`. Retrieve route
snapshots with `/api/0.6/relation/<id>/full.json`, find the stop nodes' parent
stop-area relations with `/api/0.6/node/<id>/relations.json`, and retrieve those
areas using the relation-full API. Supply an inspected snapshot directory and
explicit review dates:

```powershell
python tools/build_local_rail_graph.py --source-dir PATH_TO_INSPECTED_SNAPSHOTS --reviewed-on 2026-11-08T16:00:00Z --valid-until 2026-12-08T16:00:00Z
```

Do not advance review dates without checking the underlying data. The builder
requires adjacent catalog stations and an actual connected rail-node path.
It deliberately does not import OSM duration, interval, opening-hours or fare
tags. OSM attribution and ODbL terms accompany the derived database in
[`OSM_DATA_LICENSE.md`](../assets/transit/OSM_DATA_LICENSE.md).

## Timing and fares

Real bundled rail journeys currently provide **instructions without a total ETA**.
Only pedestrian durations come from actual OSRM responses. A modeled total
requires reviewed ride times for every edge, boarding waits, and station
entry/exit times for each boarding/alighting. These inputs are absent. Total,
arrival and departure advice stay unavailable; no train schedules are invented.
Synthetic regression fixtures demonstrate the modeled timing/leave-time path,
but are not production travel-time data. Driving retains its own base duration
and configurable 30-minute allowance, separately labeled as not real-time traffic.

The independently inspected [LRTA fare page](https://www.lrta.gov.ph/tickets-and-fares/)
and its [LRT-2 stored-value matrix](https://www.lrta.gov.ph/wp-content/uploads/2026/04/Discount_Matrix_OriginSVC_SJT_1.png)
support the checked-in LRT-2 stored-value product. The estimate identifies that
product; it is not a single-journey ticket quote. No further student discount is
stacked on the published discounted matrix. The reviewed table expires with
its explicit review window. LRT-1/MRT-3 fares are unavailable pending independent
matrix verification. Total fare appears only if every non-walking leg is priced.
The existing LTFRB calculator handles individually verified bus/jeepney legs
with supported vehicle category and traveled distance; no new unverified road
transit services were added.

## Historical and scheduled transit

Sakay GTFS remains separate historical reference data, ending June 2020. No
calendar was extended and no historical trip is used for recommendations.
There is no running OTP engine or current operator GTFS feed on this machine.
The optional Docker/backend setup remains prepared, with its validation guards.
The downloaded OSM relation snapshots are not an OTP-ready regional PBF.

Sakay's web map/utility code informed leg grouping and route selection;
Gateway's `OpenTripPlanner.scala` and `RouteHandler.scala` informed structured
itineraries/instructions. `Fare.scala` was useful as a warning to separate fares
from route discovery. The old endpoints, API keys, configuration secrets and
historical fare amounts were not copied. Commute Guide was reference reading;
its CC BY-NC-SA content/assets were not incorporated. See the earlier
[Sakay audit](sakay-otp-integration.md) for the archive analysis.

## Validation

`test/local_transit_test.dart` covers directed connectivity, boarding constraints,
explicit transfers, actual bundled geometry, pedestrian access failure,
ranking, complete/missing timing, fares and responsive results. Existing OSRM,
OTP, authentication, schedule, map and historical-data regressions remain.

```powershell
flutter analyze
flutter test
flutter build web
python -m unittest discover -s tools -p test_build_local_rail_graph.py
flutter test --dart-define=LIVE_LOCAL_TRANSIT=true test/local_transit_live_test.dart
```

The last command is opt-in and contacts the public OSRM foot router. It checks
real pedestrian responses plus the bundled graph from near Katipunan to FEU
Tech, writes `.dart_tool/local_graph/live-probe.json`, and requires connected
instructions with geometry while asserting **no total ETA**. It does not test
train operation or claim an OTP scheduled itinerary. Default tests skip this
network probe.
