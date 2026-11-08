import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Reviewed network topology is distinct from a timetable. Historical GTFS
/// and station proximity alone never authorize an edge in this graph.
class NetworkReview {
  const NetworkReview(this.source, this.reviewedOn, this.validUntil);
  final String source;
  final DateTime reviewedOn, validUntil;
  bool current(DateTime now) =>
      !now.isBefore(reviewedOn) && now.isBefore(validUntil);
  factory NetworkReview.fromJson(Map data) {
    final source = data['source_url'] as String;
    final uri = Uri.parse(source);
    final review = NetworkReview(
      source,
      DateTime.parse(data['reviewed_on'] as String),
      DateTime.parse(data['valid_until'] as String),
    );
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !review.validUntil.isAfter(review.reviewedOn)) {
      throw const FormatException('Invalid network review');
    }
    return review;
  }
}

class GraphStop {
  const GraphStop({
    required this.id,
    required this.name,
    required this.point,
    required this.review,
    this.board = true,
    this.alight = true,
    this.entryTime,
    this.exitTime,
    this.timingReview,
  });
  final String id, name;

  /// Mapped public entrance when boarding/alighting is enabled; otherwise a
  /// station reference point that must never authorize pedestrian access.
  final LatLng point;
  final NetworkReview review;
  final bool board, alight;
  final Duration? entryTime, exitTime;
  final NetworkReview? timingReview;
}

class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.line,
    required this.direction,
    required this.review,
    this.vehicle = 'RAIL',
    this.geometry = const [],
    this.rideTime,
    this.boardingWait,
    this.timingReview,
    this.lineUri,
    this.agencyUri,
    this.traveledMeters,
    this.board = true,
    this.alight = true,
  });
  final String id, from, to, line, direction, vehicle;
  final NetworkReview review;
  final List<LatLng> geometry;
  final Duration? rideTime, boardingWait;
  final NetworkReview? timingReview;
  final String? lineUri, agencyUri;
  // Independently reviewed traveled distance, never inferred for a fare from
  // straight lines or from a displayed polyline.
  final double? traveledMeters;
  final bool board, alight;
  String get service => '$line|$direction';
  bool timedAt(DateTime now) =>
      rideTime != null && timingReview?.current(now) == true;
}

class GraphTransfer {
  const GraphTransfer(this.from, this.to, this.review);
  final String from, to;
  final NetworkReview review;
}

class TransitGraph {
  TransitGraph({
    required this.stops,
    required this.edges,
    this.transfers = const [],
  }) {
    if (stops.map((s) => s.id).toSet().length != stops.length ||
        edges.map((e) => e.id).toSet().length != edges.length ||
        edges.any(
          (e) =>
              !byId.containsKey(e.from) ||
              !byId.containsKey(e.to) ||
              e.from == e.to,
        ) ||
        transfers.any(
          (e) =>
              !byId.containsKey(e.from) ||
              !byId.containsKey(e.to) ||
              e.from == e.to,
        )) {
      throw const FormatException(
        'Disconnected identities or duplicate graph IDs',
      );
    }
  }
  final List<GraphStop> stops;
  final List<GraphEdge> edges;
  final List<GraphTransfer> transfers;
  late final Map<String, GraphStop> byId = {
    for (final stop in stops) stop.id: stop,
  };

  factory TransitGraph.fromJsonString(String source) {
    final data = jsonDecode(source) as Map;
    if (data['status'] != 'reviewed_network_model') {
      throw const FormatException(
        'Historical/unverified data cannot authorize local routing',
      );
    }
    LatLng point(List p) {
      final lon = (p[0] as num).toDouble(), lat = (p[1] as num).toDouble();
      if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
        throw const FormatException('Invalid GeoJSON coordinate');
      }
      return LatLng(lat, lon);
    }

    Duration? seconds(dynamic value) {
      if (value == null) return null;
      if (value is! num || !value.isFinite || value < 0) {
        throw const FormatException('Invalid duration');
      }
      return Duration(microseconds: (value * 1000000).round());
    }

    final stops = [
      for (final raw in data['stops'] as List)
        GraphStop(
          id: raw['id'] as String,
          name: raw['name'] as String,
          point: point(raw['access_coordinates'] as List),
          review: NetworkReview.fromJson(raw['review'] as Map),
          entryTime: seconds(raw['entry_seconds']),
          exitTime: seconds(raw['exit_seconds']),
          timingReview: raw['timing_review'] == null
              ? null
              : NetworkReview.fromJson(raw['timing_review'] as Map),
          board: raw['boarding_allowed'] != false,
          alight: raw['alighting_allowed'] != false,
        ),
    ];
    final edges = <GraphEdge>[];
    for (final raw in data['edges'] as List) {
      final geometry = raw['geometry'] as Map?;
      if (geometry != null && geometry['type'] != 'LineString') {
        throw const FormatException(
          'An edge must contain one connected LineString',
        );
      }
      final points = [
        for (final p in geometry?['coordinates'] as List? ?? [])
          point(p as List),
      ];
      if (points.length == 1) {
        throw const FormatException('Incomplete edge geometry');
      }
      final meters = raw['traveled_meters'];
      if (meters != null &&
          (meters is! num || !meters.isFinite || meters <= 0)) {
        throw const FormatException('Invalid traveled distance');
      }
      edges.add(
        GraphEdge(
          id: raw['id'] as String,
          from: raw['from'] as String,
          to: raw['to'] as String,
          line: raw['line'] as String,
          direction: raw['direction'] as String,
          vehicle: raw['vehicle'] as String? ?? 'RAIL',
          review: NetworkReview.fromJson(raw['review'] as Map),
          geometry: points,
          rideTime: seconds(raw['ride_seconds']),
          boardingWait: seconds(raw['boarding_wait_seconds']),
          timingReview: raw['timing_review'] == null
              ? null
              : NetworkReview.fromJson(raw['timing_review'] as Map),
          lineUri: raw['line_uri'] as String?,
          agencyUri: raw['agency_uri'] as String?,
          board: raw['boarding_allowed'] != false,
          alight: raw['alighting_allowed'] != false,
          traveledMeters: (meters as num?)?.toDouble(),
        ),
      );
    }
    return TransitGraph(
      stops: stops,
      edges: edges,
      transfers: [
        for (final raw in data['transfers'] as List)
          GraphTransfer(
            raw['from'] as String,
            raw['to'] as String,
            NetworkReview.fromJson(raw['review'] as Map),
          ),
      ],
    );
  }
}

/// Search costs are topology preferences, NOT estimated travel minutes.
/// Uniform-cost (Dijkstra) search enumerates up to three loop-free alternatives.
class GraphPath {
  const GraphPath(
    this.stop,
    this.legs,
    this.visited,
    this.cost,
    this.lastService,
  );
  final String stop;
  final List<GraphEdge> legs;
  final Set<String> visited;
  final double cost;
  final String? lastService;
}

List<List<GraphEdge>> searchGraph(
  TransitGraph graph,
  String from,
  String to, {
  required DateTime now,
  List<GraphEdge> walkingTransfers = const [],
  int limit = 3,
  double transferPenalty = 4,
}) {
  if (from == to ||
      graph.byId[from]?.board != true ||
      graph.byId[to]?.alight != true) {
    return [];
  }
  final links = <String, List<GraphEdge>>{};
  for (final edge in [...graph.edges, ...walkingTransfers]) {
    if (edge.review.current(now) &&
        graph.byId[edge.from]!.review.current(now) &&
        graph.byId[edge.to]!.review.current(now)) {
      (links[edge.from] ??= []).add(edge);
    }
  }
  final queue = [
    GraphPath(from, const [], {from}, 0, null),
  ];
  final result = <List<GraphEdge>>[];
  var expanded = 0;
  while (queue.isNotEmpty && result.length < limit && expanded++ < 5000) {
    queue.sort((a, b) => a.cost.compareTo(b.cost));
    final current = queue.removeAt(0);
    if (current.stop == to) {
      if (current.legs.isNotEmpty &&
          current.legs.first.vehicle != 'WALK' &&
          current.legs.last.vehicle != 'WALK' &&
          current.legs.last.alight) {
        result.add(current.legs);
      }
      continue;
    }
    for (final edge in links[current.stop] ?? <GraphEdge>[]) {
      if (current.visited.contains(edge.to)) continue;
      final walk = edge.vehicle == 'WALK';
      final change =
          !walk &&
          current.lastService != null &&
          current.lastService != edge.service;
      final previous = current.legs.lastOrNull;
      if ((!walk &&
              (previous == null || previous.vehicle == 'WALK' || change) &&
              (!graph.byId[edge.from]!.board || !edge.board)) ||
          ((walk || change) &&
              previous != null &&
              previous.vehicle != 'WALK' &&
              (!graph.byId[edge.from]!.alight || !previous.alight))) {
        continue;
      }
      // Changing lines at co-located names is impossible unless explicit graph
      // identities/transfer links support it; names and proximity are ignored.
      queue.add(
        GraphPath(
          edge.to,
          [...current.legs, edge],
          {...current.visited, edge.to},
          current.cost + 1 + (change ? transferPenalty : 0),
          walk ? current.lastService : edge.service,
        ),
      );
    }
  }
  return result;
}
