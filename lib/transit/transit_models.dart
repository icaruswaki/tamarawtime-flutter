import 'dart:convert';

class TransitStop {
  final String id;
  final String name;
  final double lat;
  final double lon;
  const TransitStop(this.id, this.name, this.lat, this.lon);

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    final stop = TransitStop(
      json['id'] as String,
      json['name'] as String,
      (json['lat'] as num).toDouble(),
      (json['lon'] as num).toDouble(),
    );
    if (stop.id.isEmpty ||
        stop.name.isEmpty ||
        !stop.lat.isFinite ||
        !stop.lon.isFinite ||
        stop.lat.abs() > 90 ||
        stop.lon.abs() > 180) {
      throw const FormatException('Invalid historical stop');
    }
    return stop;
  }
}

class TransitRoute {
  final String id;
  final String name;
  final String mode;
  final bool historical;
  const TransitRoute(this.id, this.name, this.mode, this.historical);

  factory TransitRoute.fromJson(Map<String, dynamic> json) => TransitRoute(
    json['id'] as String,
    json['name'] as String,
    json['mode'] as String,
    true, // This catalog can never authorize a current service.
  );
}

/// Data is for historical exploration ONLY. Never call an itinerary 'live'.
class TransitCatalog {
  final List<TransitStop> stops;
  final List<TransitRoute> routes;
  final Map<String, List<String>> routeStops;
  final String dataStatus;
  final String source;

  const TransitCatalog(
    this.stops,
    this.routes,
    this.routeStops,
    this.dataStatus, {
    this.source = 'Unspecified historical source',
  });

  factory TransitCatalog.fromJsonString(String input) {
    final data = jsonDecode(input) as Map<String, dynamic>;
    final raw = data['route_stops'] as Map<String, dynamic>? ?? {};
    final status = data['data_status'] as String? ?? 'unverified_historical';
    if (!{'unverified_historical', 'no_verified_live_data'}.contains(status)) {
      throw const FormatException(
        'Only unverified historical catalogs are supported',
      );
    }
    final catalog = TransitCatalog(
      (data['stops'] as List<dynamic>)
          .map((e) => TransitStop.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      (data['routes'] as List<dynamic>)
          .map(
            (e) => TransitRoute.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      raw.map((key, value) => MapEntry(key, List<String>.from(value as List))),
      status,
      source: data['source'] as String? ?? 'Unspecified historical source',
    );
    final stops = catalog.stops.map((s) => s.id).toSet();
    final routes = catalog.routes.map((r) => r.id).toSet();
    if (stops.length != catalog.stops.length ||
        routes.length != catalog.routes.length ||
        routes.contains('') ||
        catalog.routeStops.entries.any(
          (entry) =>
              !routes.contains(entry.key) ||
              entry.value.any((id) => !stops.contains(id)),
        )) {
      throw const FormatException(
        'Invalid historical route or stop references',
      );
    }
    return catalog;
  }

  TransitStop? stopById(String id) {
    for (final stop in stops) {
      if (stop.id == id) return stop;
    }
    return null;
  }

  List<TransitRoute> routesServingStop(String id) => routes
      .where((route) => (routeStops[route.id] ?? const []).contains(id))
      .toList();
}
