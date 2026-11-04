import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const campusPoints = <String, LatLng>{
  'FEU Tech': LatLng(14.6043, 120.9884),
  'FEU Manila': LatLng(14.6046, 120.9867),
  'FEU Diliman': LatLng(14.6994, 121.0648),
  'FEU Alabang': LatLng(14.4195, 121.0438),
};

class RoutePlan {
  RoutePlan(this.points, this.minutes, this.meters);
  final List<LatLng> points;
  final int minutes;
  final double meters;
}

class JeepneyPlan {
  JeepneyPlan(
    this.name,
    this.board,
    this.alight,
    this.boardName,
    this.alightName,
    this.points,
  );
  final String name, boardName, alightName;
  final LatLng board, alight;
  final List<LatLng> points;
}

class Routing {
  static Future<dynamic> get(Uri uri) async {
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'TamarawTime/1.0 (open-source Flutter app)',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Map service unavailable (${response.statusCode})');
    }
    return jsonDecode(response.body);
  }

  static String roadProfile(String mode) => mode == 'Walking' ? 'foot' : 'car';

  static Future<RoutePlan> road(LatLng from, LatLng to, String mode) async {
    final profile = roadProfile(mode);
    final data = await get(
      Uri.parse(
        'https://routing.openstreetmap.de/routed-$profile/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson',
      ),
    );
    final routes = data['routes'] as List? ?? [];
    if (routes.isEmpty) throw Exception('No route returned');
    final r = routes.first;
    return RoutePlan(
      points(r['geometry']['coordinates']),
      ((r['duration'] as num) / 60).ceil().clamp(1, 10000),
      (r['distance'] as num).toDouble(),
    );
  }

  static List<LatLng> points(dynamic coordinates) => (coordinates as List)
      .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
      .toList();

  static List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
    final result = <LatLng>[];
    var index = 0, latitude = 0, longitude = 0;
    final factor = pow10(precision);
    while (index < encoded.length) {
      int decode() {
        var value = 0, shift = 0, byte = 0;
        do {
          byte = encoded.codeUnitAt(index++) - 63;
          value |= (byte & 0x1f) << shift;
          shift += 5;
        } while (byte >= 0x20);
        return (value & 1) == 1 ? -(value >> 1) : (value >> 1);
      }

      latitude += decode();
      longitude += decode();
      result.add(LatLng(latitude / factor, longitude / factor));
    }
    return result;
  }

  static double pow10(int precision) {
    var value = 1.0;
    for (var i = 0; i < precision; i++) value *= 10;
    return value;
  }

  static Future<RoutePlan?> railways(LatLng from, LatLng to) async {
    final midpoint = LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );
    final query = '[out:json][timeout:12];way(around:12000,${midpoint.latitude},${midpoint.longitude})["railway"~"^(rail|light_rail|subway)\$"];out geom;';

    Future<dynamic> fetch(String host) async {
      try {
        final response = await http.post(
          Uri.https(host, '/api/interpreter'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': 'TamarawTime/1.0 (open-source Flutter app)',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;
        return jsonDecode(response.body);
      } catch (_) {
        return null;
      }
    }

    dynamic data;
    for (final result in await Future.wait([
      fetch('overpass-api.de'),
      fetch('overpass.kumi.systems'),
    ])) {
      if (result != null) {
        data = result;
        break;
      }
    }
    if (data == null) return null;

    final elements = data['elements'] as List? ?? [];
    const distance = Distance();
    final nodes = <LatLng>[];
    final nodeIndex = <String, int>{};
    final adjacency = <List<int>>[];

    int indexFor(LatLng point) {
      final key = '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
      final existing = nodeIndex[key];
      if (existing != null) return existing;
      final index = nodes.length;
      nodeIndex[key] = index;
      nodes.add(point);
      adjacency.add(<int>[]);
      return index;
    }

    for (final element in elements) {
      final geometry = (element['geometry'] as List?) ?? const [];
      final points = geometry.map((node) => LatLng(
        (node['lat'] as num).toDouble(),
        (node['lon'] as num).toDouble(),
      )).toList();
      if (points.length < 2) continue;
      for (var i = 0; i < points.length; i++) {
        final current = indexFor(points[i]);
        if (i == 0) continue;
        final previous = indexFor(points[i - 1]);
        if (!adjacency[current].contains(previous)) adjacency[current].add(previous);
        if (!adjacency[previous].contains(current)) adjacency[previous].add(current);
      }
    }
    if (nodes.isEmpty) return null;

    int nearest(LatLng point) {
      var nearestIndex = 0;
      var nearestMeters = double.infinity;
      for (var i = 0; i < nodes.length; i++) {
        final meters = distance(point, nodes[i]);
        if (meters < nearestMeters) {
          nearestMeters = meters;
          nearestIndex = i;
        }
      }
      return nearestIndex;
    }

    final start = nearest(from), target = nearest(to);
    if (distance(from, nodes[start]) > 15000 || distance(to, nodes[target]) > 15000) return null;

    final costs = List<double>.filled(nodes.length, double.infinity);
    final previous = List<int>.filled(nodes.length, -1);
    final visited = List<bool>.filled(nodes.length, false);
    costs[start] = 0;
    for (var count = 0; count < nodes.length; count++) {
      var current = -1;
      var currentCost = double.infinity;
      for (var i = 0; i < nodes.length; i++) {
        if (!visited[i] && costs[i] < currentCost) {
          current = i;
          currentCost = costs[i];
        }
      }
      if (current < 0 || current == target) break;
      visited[current] = true;
      for (final next in adjacency[current]) {
        final candidate = currentCost + distance(nodes[current], nodes[next]);
        if (candidate < costs[next]) {
          costs[next] = candidate;
          previous[next] = current;
        }
      }
    }
    if (previous[target] < 0 && start != target) return null;

    final pathIndexes = <int>[];
    for (var current = target; current >= 0; current = previous[current]) {
      pathIndexes.add(current);
      if (current == start) break;
    }
    if (pathIndexes.last != start) return null;
    final orderedIndexes = pathIndexes.reversed.toList();

    var railMeters = 0.0;
    final railPoints = <LatLng>[];
    for (final index in orderedIndexes) {
      if (railPoints.isNotEmpty) railMeters += distance(railPoints.last, nodes[index]);
      railPoints.add(nodes[index]);
    }
    final totalMeters = distance(from, railPoints.first) + railMeters + distance(railPoints.last, to);
    final minutes = ((totalMeters / 533.333333) + 12).ceil().clamp(1, 10000);
    return RoutePlan(<LatLng>[from, ...railPoints, to], minutes, totalMeters);
  }

  static Future<RoutePlan> transit(
    LatLng from,
    LatLng to,
    String mode,
  ) async {
    final railFuture = mode == 'Train'
        ? railways(from, to)
        : Future<RoutePlan?>.value(null);
    final transitModes = switch (mode) {
      'Train' => 'RAIL,SUBURBAN,SUBWAY',
      'Bus / UV' => 'BUS,COACH',
      _ => 'TRANSIT',
    };
    final uri = Uri.https('api.transitous.org', '/api/v6/plan', {
      'fromPlace': '${from.latitude},${from.longitude}',
      'toPlace': '${to.latitude},${to.longitude}',
      'time': DateTime.now().toUtc().toIso8601String(),
      'transitModes': transitModes,
      'directModes': 'WALK,CAR',
      'numItineraries': '3',
      'timetableView': 'false',
      'detailedLegs': 'true',
      'language': 'en',
    });
    dynamic data;
    try {
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'TamarawTime/1.0 (open-source Flutter app)'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) data = jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (data == null) {
      if (mode == 'Train') {
        final rail = await railFuture;
        if (rail != null) return rail;
      }
      final roadRoute = await road(from, to, 'Driving');
      final factor = switch (mode) {
        'Train' => 0.90,
        'Bus / UV' => 1.15,
        _ => 1.25,
      };
      return RoutePlan(
        roadRoute.points,
        (roadRoute.minutes * factor).ceil().clamp(1, 10000),
        roadRoute.meters,
      );
    }
    final itineraries = data['itineraries'] as List? ?? [];
    if (itineraries.isEmpty) {
      if (mode == 'Train') {
        final rail = await railFuture;
        if (rail != null) return rail;
      }
      final roadRoute = await road(from, to, 'Driving');
      final factor = switch (mode) {
        'Train' => 0.90,
        'Bus / UV' => 1.15,
        _ => 1.25,
      };
      return RoutePlan(
        roadRoute.points,
        (roadRoute.minutes * factor).ceil().clamp(1, 10000),
        roadRoute.meters,
      );
    }

    Map itinerary;
    if (mode == 'Train') {
      itinerary = itineraries.cast<Map>().firstWhere(
        (candidate) {
          final legs = candidate['legs'] as List? ?? [];
          return legs.any((leg) => const {
            'RAIL', 'SUBURBAN', 'SUBWAY', 'TRAM', 'REGIONAL_RAIL',
            'HIGHSPEED_RAIL', 'LONG_DISTANCE', 'NIGHT_RAIL'
          }.contains(leg['mode']));
        },
        orElse: () => <String, dynamic>{},
      );
      if (itinerary.isEmpty) {
        final rail = await railFuture;
        if (rail != null) return rail;
        throw Exception('No Train itinerary with mapped rail service was found');
      }
    } else {
      itinerary = itineraries.first as Map;
    }
    final legs = itinerary['legs'] as List? ?? [];
    final routePoints = <LatLng>[];
    var meters = 0.0;
    for (final leg in legs) {
      meters += (leg['distance'] is num)
          ? (leg['distance'] as num).toDouble()
          : 0.0;
      final geometry = leg['legGeometry'] as Map?;
      final encoded = geometry?['points'];
      if (encoded is String && encoded.isNotEmpty) {
        final precision = (geometry?['precision'] as num?)?.toInt() ?? 6;
        routePoints.addAll(decodePolyline(encoded, precision: precision));
      }
    }
    final duration = (itinerary['duration'] as num?)?.toDouble() ?? 0;
    if (duration <= 0) throw Exception('Transit connection returned no duration');
    return RoutePlan(routePoints, (duration / 60).ceil(), meters);
  }
  static bool isJeepney(Map tags) {
    if (!['bus', 'jeepney', 'share_taxi'].contains(tags['route'])) return false;
    final text = [
      'bus',
      'vehicle',
      'vehicle:type',
      'service',
      'route:type',
      'name',
      'description',
      'network',
    ].map((k) => tags[k] ?? '').join(' ').toLowerCase();
    if (RegExp('uv express|uvx|van service|p2p bus|edsa carousel')
        .hasMatch(text)) {
      return false;
    }
    return tags['route'] == 'jeepney' ||
        RegExp(r'jeepney|jeep|share_taxi|\bpuj\b').hasMatch(text) ||
        RegExp(
          r'^T\d{2,4}[A-Z]?$',
          caseSensitive: false,
        ).hasMatch('${tags['ref'] ?? ''}') ||
        (tags['route'] == 'bus' &&
            (RegExp(r'^\d{1,3}[A-Z]?$', caseSensitive: false)
                    .hasMatch('${tags['ref'] ?? ''}') ||
                RegExp(r'route\s*\d{1,3}\b', caseSensitive: false)
                    .hasMatch(text))) ;
  }

  static Future<List<JeepneyPlan>> jeepneys(LatLng from, LatLng to) async {
    for (final p in [from, to]) {
      if (p.latitude < 14.30 ||
          p.latitude > 14.92 ||
          p.longitude < 120.85 ||
          p.longitude > 121.22) {
        throw Exception('Jeepney discovery covers Metro Manila only.');
      }
    }
    final query = '[out:json][timeout:18];('
        'relation(around:3500,${from.latitude},${from.longitude})["type"="route"]["route"~"^(bus|jeepney|share_taxi)"]["name"];'
        'relation(around:3500,${to.latitude},${to.longitude})["type"="route"]["route"~"^(bus|jeepney|share_taxi)"]["name"];'
        ');out tags;';
    Future<dynamic> fetchRelations(String host) async {
      try {
        final response = await http
            .post(
              Uri.https(host, '/api/interpreter'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'User-Agent': 'TamarawTime/1.0 (open-source Flutter app)',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return null;
        return jsonDecode(response.body);
      } catch (_) {
        return null;
      }
    }

    dynamic data;
    for (final result in await Future.wait([
      fetchRelations('overpass-api.de'),
      fetchRelations('overpass.kumi.systems'),
    ])) {
      if (result != null) {
        data = result;
        break;
      }
    }
    if (data == null) {
      return [];
    }
    final relations = ((data['elements'] as List?) ?? const [])
        .where((e) => isJeepney(e['tags'] as Map? ?? {}))
        .take(6);
    final found = <JeepneyPlan>[];
    int failures = 0;
    const distance = Distance();
    for (final relation in relations) {
      try {
        final response = await http.get(
          Uri.parse(
            'https://openstreetmap.tools/public_transport_geojson/api/route/${relation['id']}',
          ),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'TamarawTime/1.0 (open-source Flutter app)',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;
        final detail = jsonDecode(response.body);
        final stops = (detail['stops'] as List? ?? [])
            .where((s) => s['lat'] is num && (s['lon'] ?? s['lng']) is num)
            .toList();
        LatLng point(dynamic s) => LatLng(
          (s['lat'] as num).toDouble(),
          ((s['lon'] ?? s['lng']) as num).toDouble(),
        );
        double best = double.infinity;
        int bi = -1, ai = -1;
        for (int i = 0; i < stops.length - 1; i++) {
          final a = point(stops[i]), access = distance(from, point(stops[i]));
          if (access > 900) continue;
          for (int j = i + 1; j < stops.length; j++) {
            final b = point(stops[j]), exit = distance(to, point(stops[j]));
            if (exit > 1200 ||
                distance(a, b) < 300 ||
                access + exit + 300 >= distance(from, b) + distance(to, a)) {
              continue;
            }
            if (access + exit < best) {
              best = access + exit;
              bi = i;
              ai = j;
            }
          }
        }
        if (bi < 0) continue;
        final features = detail['geojson']?['features'] as List? ?? [];
        final lines = features.where(
          (f) => f['geometry']?['type'] == 'LineString',
        );
        if (lines.isEmpty) continue;
        if (bi < 0 && stops.isEmpty) {
          final coordinates = lines.first['geometry']['coordinates'] as List? ?? const [];
          final geometry = points(coordinates);
          if (geometry.length < 2) continue;
          var originIndex = 0, destinationIndex = 0;
          var originScore = double.infinity, destinationScore = double.infinity;
          for (var i = 0; i < geometry.length; i++) {
            final originDistance = distance(from, geometry[i]);
            final destinationDistance = distance(to, geometry[i]);
            if (originDistance < originScore) {
              originScore = originDistance;
              originIndex = i;
            }
            if (destinationDistance < destinationScore) {
              destinationScore = destinationDistance;
              destinationIndex = i;
            }
          }
          if (originScore > 1500 || destinationScore > 1500) continue;
          var firstIndex = originIndex < destinationIndex ? originIndex : destinationIndex;
          var secondIndex = originIndex < destinationIndex ? destinationIndex : originIndex;
          if (secondIndex - firstIndex < 0) continue;
          final board = geometry[firstIndex];
          final alight = geometry[secondIndex];
          found.add(
            JeepneyPlan(
              '${detail['name'] ?? relation['tags']['name'] ?? 'Mapped jeepney route'}',
              board,
              alight,
              'Nearest mapped point',
              'Nearest mapped point',
              geometry,
            ),
          );
          if (found.length == 3) break;
          continue;
        }
        if (bi < 0) continue;
        found.add(
          JeepneyPlan(
            '${detail['name'] ?? relation['tags']['name'] ?? 'Mapped jeepney'}',
            point(stops[bi]),
            point(stops[ai]),
            '${stops[bi]['name'] ?? 'Mapped boarding stop'}',
            '${stops[ai]['name'] ?? 'Mapped alighting stop'}',
            points(lines.first['geometry']['coordinates']),
          ),
        );
        if (found.length == 3) break;
      } catch (_) {
        failures++;
      }
    }
    if (found.isEmpty && failures > 0) {
      throw Exception('Route detail service unavailable. Try again later.');
    }
    return found;
  }
}
