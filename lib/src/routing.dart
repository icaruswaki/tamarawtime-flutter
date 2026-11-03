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
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Map service unavailable (${response.statusCode})');
    }
    return jsonDecode(response.body);
  }

  static Future<RoutePlan> road(LatLng from, LatLng to, String mode) async {
    final profile = mode == 'Walking' ? 'foot' : 'driving';
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
        ).hasMatch('${tags['ref'] ?? ''}');
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
    final query =
        '[out:json][timeout:16];relation(around:1400,${from.latitude},${from.longitude})["type"="route"]["route"~"^(bus|jeepney|share_taxi)\$"];out tags;';
    dynamic data;
    for (final host in ['overpass-api.de', 'overpass.kumi.systems']) {
      try {
        final response = await http
            .post(Uri.https(host, '/api/interpreter'), body: {'data': query})
            .timeout(const Duration(seconds: 22));
        if (response.statusCode != 200) throw Exception('Map data unavailable');
        data = jsonDecode(response.body);
        break;
      } catch (_) {
        if (host == 'overpass.kumi.systems') rethrow;
      }
    }
    final relations = (data['elements'] as List)
        .where((e) => isJeepney(e['tags'] as Map? ?? {}))
        .take(12);
    final found = <JeepneyPlan>[];
    int failures = 0;
    const distance = Distance();
    for (final relation in relations) {
      try {
        final detail = await get(
          Uri.parse(
            'https://openstreetmap.tools/public_transport_geojson/api/route/${relation['id']}',
          ),
        );
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
            if (exit > 900 ||
                distance(a, b) < 300 ||
                access + exit + 150 >= distance(from, b) + distance(to, a)) {
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
