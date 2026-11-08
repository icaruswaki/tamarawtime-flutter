import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../src/journey.dart';
import '../src/routing.dart';
import 'local_transit_graph.dart';

typedef PedestrianRouter = Future<RoutePlan> Function(LatLng, LatLng, String);

class LocalTransitProvider implements JourneyProvider, TransitAvailability {
  LocalTransitProvider({
    this.walk = Routing.road,
    Future<TransitGraph> Function()? load,
    DateTime Function()? now,
  }) : load = load ?? loadBundledGraph,
       now = now ?? DateTime.now;
  final PedestrianRouter walk;
  final Future<TransitGraph> Function() load;
  final DateTime Function() now;
  Future<TransitGraph>? _graph;
  @override
  String? transitUnavailableReason;

  static Future<TransitGraph> loadBundledGraph() async =>
      TransitGraph.fromJsonString(
        await rootBundle.loadString('assets/transit/local_transit_graph.json'),
      );

  Future<RoutePlan?> _pedestrian(
    LatLng from,
    LatLng to,
    double maxMeters,
  ) async {
    try {
      final route = await walk(from, to, 'Walking');
      const distance = Distance();
      if (route.points.length < 2 ||
          route.meters > maxMeters ||
          route.duration <= Duration.zero ||
          distance(route.points.first, from) > 80 ||
          distance(route.points.last, to) > 80) {
        return null;
      }
      return route;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<JourneyOption>> fetch(JourneyQuery query) async {
    if (!{'Transit', 'Train', 'Bus / UV', 'Jeepney'}.contains(query.mode)) {
      return [];
    }
    transitUnavailableReason = null;
    final clock = now().toUtc();
    final reviewTime = query.arriveBy ?? clock;
    TransitGraph graph;
    try {
      graph = await (_graph ??= load());
    } catch (_) {
      _graph = null;
      transitUnavailableReason =
          'The reviewed local transit network could not be loaded.';
      return [];
    }
    if (graph.stops.isEmpty || graph.edges.isEmpty) {
      transitUnavailableReason = 'Local routing needs reviewed station access coordinates and connected transit edges. Station names and historical routes alone cannot establish a journey.';
      return [];
    }
    const distance = Distance();
    List<GraphStop> nearby(LatLng point, bool boarding) =>
        graph.stops
            .where(
              (s) =>
                  (boarding ? s.board : s.alight) &&
                  s.review.current(reviewTime) &&
                  distance(s.point, point) <= 1800,
            )
            .toList()
          ..sort(
            (a, b) =>
                distance(a.point, point).compareTo(distance(b.point, point)),
          );
    final access = <String, RoutePlan>{}, egress = <String, RoutePlan>{};
    // Small bounded candidate set. Straight-line distance only prefilters; a
    // successful pedestrian route is mandatory before a station is usable.
    for (final stop in nearby(query.origin, true).take(3)) {
      final route = await _pedestrian(query.origin, stop.point, 2200);
      if (route != null) access[stop.id] = route;
    }
    for (final stop in nearby(query.destination, false).take(3)) {
      final route = await _pedestrian(stop.point, query.destination, 2200);
      if (route != null) egress[stop.id] = route;
    }
    final transfers = <GraphEdge>[];
    if (access.isNotEmpty && egress.isNotEmpty) {
      for (final link in graph.transfers.where(
        (t) => t.review.current(reviewTime),
      )) {
        final route = await _pedestrian(
          graph.byId[link.from]!.point,
          graph.byId[link.to]!.point,
          1200,
        );
        if (route == null) continue;
        transfers.add(
          GraphEdge(
            id: 'walk-${link.from}-${link.to}',
            from: link.from,
            to: link.to,
            line: 'Walking transfer',
            direction: graph.byId[link.to]!.name,
            review: link.review,
            vehicle: 'WALK',
            geometry: route.points,
            rideTime: route.duration,
            timingReview: link.review,
            traveledMeters: route.meters,
          ),
        );
      }
    }
    final options = <JourneyOption>[];
    final seen = <String>{};
    for (final a in access.entries) {
      for (final b in egress.entries) {
        for (final path in searchGraph(
          graph,
          a.key,
          b.key,
          now: reviewTime,
          walkingTransfers: transfers,
        )) {
          if (query.mode == 'Train' &&
              path.any(
                (e) => !{'WALK', 'RAIL', 'SUBWAY', 'TRAM'}.contains(e.vehicle),
              )) {
            continue;
          }
          if (query.mode == 'Bus / UV' &&
              path.any((e) => !{'WALK', 'BUS'}.contains(e.vehicle))) {
            continue;
          }
          if (query.mode == 'Jeepney' &&
              path.any(
                (e) => !{'WALK', 'JEEPNEY', 'SHARE_TAXI'}.contains(e.vehicle),
              )) {
            continue;
          }
          final key = path.map((e) => e.id).join('|');
          if (!seen.add(key)) continue;
          options.add(
            _journey(graph, path, a.value, b.value, clock, reviewTime),
          );
        }
      }
    }
    options.sort(compareLocalJourneys);
    // With no total timing, avoid offering a route that is worse on every
    // known topology criterion. This is not a claim about travel minutes.
    int rideStops(JourneyOption o) => o.steps
        .where((s) => s.transit)
        .fold(0, (sum, s) => sum + (s.stops ?? 0));
    final suitable = options
        .where(
          (candidate) =>
              candidate.hasDuration ||
              !options.any(
                (other) =>
                    !identical(candidate, other) &&
                    !other.hasDuration &&
                    other.transfers <= candidate.transfers &&
                    rideStops(other) <= rideStops(candidate) &&
                    other.walkingMeters! <= candidate.walkingMeters! &&
                    (other.transfers < candidate.transfers ||
                        rideStops(other) < rideStops(candidate) ||
                        other.walkingMeters! < candidate.walkingMeters!),
              ),
        )
        .toList();
    if (options.isEmpty) transitUnavailableReason = 'No connected reviewed transit journey with pedestrian access was found within the local coverage. Walking/driving remain separate alternatives.';
    return suitable.take(3).toList();
  }

  JourneyOption _journey(
    TransitGraph graph,
    List<GraphEdge> path,
    RoutePlan access,
    RoutePlan egress,
    DateTime clock,
    DateTime reviewTime,
  ) {
    JourneyStep walking(RoutePlan route, String instruction) => JourneyStep(
      mode: 'WALK',
      instruction: instruction,
      duration: route.duration,
      meters: route.meters,
      points: route.points,
      timingSource: 'OSRM pedestrian route; no live conditions',
    );
    final steps = <JourneyStep>[
      walking(access, 'Walk to ${graph.byId[path.first.from]!.name}'),
    ];
    final limitations = <String>{
      'Network-based route; check operating hours and service notices before travelling.',
      'Follow station signs from the mapped entrance to the correct platform. Internal station paths are not mapped.',
    };
    var total = access.duration + egress.duration;
    var complete = true;
    for (var i = 0; i < path.length;) {
      final first = path[i];
      if (first.vehicle == 'WALK') {
        steps.add(
          JourneyStep(
            mode: 'WALK',
            instruction:
                'Transfer on foot from ${graph.byId[first.from]!.name} to ${graph.byId[first.to]!.name}',
            duration: first.rideTime,
            points: first.geometry,
            meters: first.traveledMeters,
            timingSource: 'OSRM pedestrian connection',
          ),
        );
        total += first.rideTime!;
        i++;
        continue;
      }
      final group = <GraphEdge>[first];
      i++;
      while (i < path.length &&
          path[i].vehicle != 'WALK' &&
          path[i].service == first.service) {
        group.add(path[i++]);
      }
      final rideKnown = group.every((e) => e.timedAt(reviewTime));
      final wait = first.timingReview?.current(reviewTime) == true
          ? first.boardingWait
          : null;
      final duration = rideKnown
          ? group.fold<Duration>(Duration.zero, (s, e) => s + e.rideTime!)
          : null;
      final boarding = graph.byId[first.from]!,
          alighting = graph.byId[group.last.to]!;
      final entry = boarding.timingReview?.current(reviewTime) == true
          ? boarding.entryTime
          : null;
      final exit = alighting.timingReview?.current(reviewTime) == true
          ? alighting.exitTime
          : null;
      if (duration == null || wait == null || entry == null || exit == null) {
        complete = false;
      } else {
        total += duration + wait + entry + exit;
      }
      final geometry = <LatLng>[];
      var geometryKnown = true;
      for (final edge in group) {
        if (edge.geometry.length < 2 ||
            (geometry.isNotEmpty &&
                const Distance()(geometry.last, edge.geometry.first) > 3)) {
          geometryKnown = false;
          break;
        }
        geometry.addAll(edge.geometry);
      }
      if (!geometryKnown) {
        limitations.add(
          'Track geometry unavailable for ${first.line}; no straight-line rail segment is drawn.',
        );
      }
      steps.add(
        JourneyStep(
          mode: 'TRANSIT',
          vehicle: first.vehicle,
          lineName: first.line,
          lineUri: first.lineUri,
          agencyUris: [if (first.agencyUri != null) first.agencyUri!],
          boardingStop: graph.byId[first.from]!.name,
          alightingStop: graph.byId[group.last.to]!.name,
          boardingPoint: graph.byId[first.from]!.point,
          alightingPoint: graph.byId[group.last.to]!.point,
          headsign: first.direction,
          stops: group.length,
          points: geometryKnown ? geometry : [],
          duration: duration,
          waitingDuration: wait,
          timingSource: rideKnown
              ? group.map((e) => e.timingReview!.source).toSet().join(', ')
              : null,
          meters: group.every((e) => e.traveledMeters != null)
              ? group.fold<double>(0, (s, e) => s + e.traveledMeters!)
              : null,
        ),
      );
    }
    steps.add(
      walking(
        egress,
        'Walk from ${graph.byId[path.last.to]!.name} to your destination',
      ),
    );
    if (!complete) {
      limitations.add(
        'Total ETA and departure advice unavailable: reviewed ride, boarding-wait or station-access times are missing.',
      );
    }
    return JourneyOption(
      id: 'local-${path.map((e) => e.id).join('-')}',
      duration: complete ? total : null,
      points: steps.expand((s) => s.points).toList(),
      steps: steps,
      updatedAt: clock,
      source: JourneySource.localGraph,
      limitations: limitations.toList(),
    );
  }
}

int compareLocalJourneys(JourneyOption a, JourneyOption b) {
  if (a.hasDuration != b.hasDuration) return a.hasDuration ? -1 : 1;
  if (a.hasDuration && b.hasDuration) {
    final time = a.duration.compareTo(b.duration);
    if (time != 0) return time;
  }
  final transfers = a.transfers.compareTo(b.transfers);
  if (transfers != 0) return transfers;
  return (a.walkingMeters ?? double.infinity).compareTo(
    b.walkingMeters ?? double.infinity,
  );
}
