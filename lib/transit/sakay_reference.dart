import 'dart:convert';

class HistoricalSakayStop {
  const HistoricalSakayStop(
    this.id,
    this.name,
    this.sequence,
    this.latitude,
    this.longitude,
  );
  final String id, name;
  final int sequence;
  final double? latitude, longitude;
  factory HistoricalSakayStop.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble(),
        lon = (json['lon'] as num?)?.toDouble();
    if (json['stop_id'] is! String ||
        (json['stop_id'] as String).isEmpty ||
        json['name'] is! String ||
        (json['sequence'] as int) < 0 ||
        ((lat == null) != (lon == null)) ||
        (lat != null && (!lat.isFinite || lat.abs() > 90)) ||
        (lon != null && (!lon.isFinite || lon.abs() > 180))) {
      throw const FormatException('Invalid historical sample stop');
    }
    return HistoricalSakayStop(
      json['stop_id'] as String,
      json['name'] as String,
      json['sequence'] as int,
      lat,
      lon,
    );
  }
}

class HistoricalSakayRoute {
  const HistoricalSakayRoute(
    this.id,
    this.name,
    this.shortName,
    this.description,
    this.mode,
    this.sampleTripId,
    this.stops,
  );
  final String id, name, shortName, description, mode;
  final String? sampleTripId;
  final List<HistoricalSakayStop> stops;
  String get classification => switch (mode) {
    'jeepney_reference' => 'Historical jeepney classification',
    'rail_reference' => 'Historical rail classification',
    _ => 'Road transit · unclassified',
  };
  bool matches(String query) =>
      '$name $shortName $id ${stops.map((s) => s.name).join(' ')}'
          .toLowerCase()
          .contains(query.toLowerCase().trim());
  factory HistoricalSakayRoute.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic> stopDefinitions = const {},
  }) {
    if (json['historical_only'] != true ||
        json['validated_current_operation'] != false ||
        !{
          'jeepney_reference',
          'rail_reference',
          'road_transit_unclassified',
        }.contains(json['mode'])) {
      throw const FormatException(
        'Historical routes cannot assert current operation',
      );
    }
    final stops = (json['ordered_stops_from_one_sample_trip'] as List).map((
      raw,
    ) {
      final visit = Map<String, dynamic>.from(raw as Map);
      if (!visit.containsKey('name')) {
        final stop = stopDefinitions[visit['stop_id']];
        if (stop is! Map) {
          throw const FormatException('Missing sample stop reference');
        }
        visit.addAll(Map<String, dynamic>.from(stop));
      }
      return HistoricalSakayStop.fromJson(visit);
    }).toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
    final route = HistoricalSakayRoute(
      json['id'] as String,
      json['name'] as String,
      json['short_name'] as String? ?? '',
      json['description'] as String? ?? '',
      json['mode'] as String,
      json['trip_example_id'] as String?,
      List.unmodifiable(stops),
    );
    if (route.id.isEmpty || route.name.isEmpty) {
      throw const FormatException('Missing historical route identity');
    }
    return route;
  }
}

class SakayHistoricalCatalog {
  const SakayHistoricalCatalog(
    this.routes,
    this.source,
    this.sourceUrl,
    this.licenseUrl,
  );
  final List<HistoricalSakayRoute> routes;
  final String source, sourceUrl, licenseUrl;
  Map<String, HistoricalSakayStop> get stops => {
    for (final route in routes)
      for (final stop in route.stops) stop.id: stop,
  };
  List<HistoricalSakayRoute> routesAt(String stopId) => routes
      .where((route) => route.stops.any((stop) => stop.id == stopId))
      .toList();
  factory SakayHistoricalCatalog.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (!{1, 2}.contains(json['schema_version']) ||
        json['status'] != 'historical_reference_only') {
      throw const FormatException('Unsupported historical Sakay catalog');
    }
    final definitions = json['schema_version'] == 2
        ? Map<String, dynamic>.from(json['stops'] as Map)
        : <String, dynamic>{};
    final routes = (json['routes'] as List)
        .map(
          (raw) => HistoricalSakayRoute.fromJson(
            Map<String, dynamic>.from(raw as Map),
            stopDefinitions: definitions,
          ),
        )
        .toList();
    if (routes.map((route) => route.id).toSet().length != routes.length) {
      throw const FormatException('Duplicate historical route ID');
    }
    return SakayHistoricalCatalog(
      List.unmodifiable(routes),
      json['source'] as String,
      json['source_url'] as String,
      json['license_url'] as String,
    );
  }
}
