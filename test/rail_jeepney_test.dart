import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tamaraw_time/transit/operating_route_source.dart';
import 'package:tamaraw_time/transit/rail_reference_repository.dart';
import 'package:tamaraw_time/transit/sakay_reference.dart';
import 'package:tamaraw_time/transit/transit_repository.dart';

class _EvidenceSource implements OperatingRouteSource {
  OperatingRouteEvidence? evidence;
  bool fail = false;
  @override
  Future<OperatingRouteEvidence?> lookup(String routeId) async {
    if (fail) throw StateError('Backend unavailable');
    return evidence;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = File('assets/transit/rail_network_2026.json')
      .readAsStringSync();
  final network = RailNetwork.fromJsonString(source);

  test(
    'Bundled rail repository loads the complete reference network',
    () async {
      expect(
        (await RailReferenceRepository().loadNetwork()).stations.length,
        51,
      );
    },
  );

  test('All 51 stations follow the supplied LRT-1, LRT-2 and MRT-3 reference order', () {
    final expected = {
      'lrt1': [
        'Fernando Poe Jr.',
        'Balintawak',
        'Monumento',
        '5th Avenue',
        'R. Papa',
        'Abad Santos',
        'Blumentritt',
        'Tayuman',
        'Bambang',
        'Doroteo Jose',
        'Carriedo',
        'Central Terminal',
        'United Nations',
        'Pedro Gil',
        'Quirino',
        'Vito Cruz',
        'Gil Puyat',
        'Libertad',
        'EDSA',
        'Baclaran',
        'Redemptorist-Aseana',
        'MIA Road',
        'PITX',
        'Ninoy Aquino Avenue',
        'Dr. Santos',
      ],
      'lrt2': [
        'Recto',
        'Legarda',
        'Pureza',
        'V. Mapa',
        'J. Ruiz',
        'Gilmore',
        'Betty Go-Belmonte',
        'Araneta Center-Cubao',
        'Anonas',
        'Katipunan',
        'Santolan',
        'Marikina-Pasig',
        'Antipolo',
      ],
      'mrt3': [
        'North Avenue',
        'Quezon Avenue',
        'GMA Kamuning',
        'Araneta-Cubao',
        'Santolan-Annapolis',
        'Ortigas',
        'Shaw Boulevard',
        'Boni',
        'Guadalupe',
        'Buendia',
        'Ayala',
        'Magallanes',
        'Taft Avenue',
      ],
    };
    expect(network.stations.length, 51);
    for (final line in network.lines) {
      expect(line.stations.map((s) => s.name), expected[line.id]);
      expect(line.beginning.terminal, isTrue);
      expect(line.ending.terminal, isTrue);
    }
    expect(network.stations.where((s) => s.terminal).length, 6);
    expect(network.station('LRT-1:Central Terminal').terminal, isFalse);
  });

  test('Three walking interchanges are available in both directions', () {
    final pairs = {
      'LRT-1:Doroteo Jose': 'LRT-2:Recto',
      'LRT-1:EDSA': 'MRT-3:Taft Avenue',
      'LRT-2:Araneta Center-Cubao': 'MRT-3:Araneta-Cubao',
    };
    expect(network.transfers, hasLength(3));
    for (final entry in pairs.entries) {
      expect(
        network.transfersAt(entry.key).single.other(entry.key),
        entry.value,
      );
      expect(
        network.transfersAt(entry.value).single.other(entry.value),
        entry.key,
      );
    }
  });

  test('Rail parser rejects broken order, missing interchange stations and live claims', () {
    final json = jsonDecode(source);
    json['lines'][0]['stations'][1]['order'] = 1;
    expect(
      () => RailNetwork.fromJsonString(jsonEncode(json)),
      throwsFormatException,
    );
    final missing = jsonDecode(source);
    missing['walking_transfers'][0]['to'] = 'invented';
    expect(
      () => RailNetwork.fromJsonString(jsonEncode(missing)),
      throwsFormatException,
    );
    final live = jsonDecode(source);
    live['status'] = 'live';
    expect(
      () => RailNetwork.fromJsonString(jsonEncode(live)),
      throwsFormatException,
    );
  });

  test('Imported Sakay catalog retains counts, historical flags, searchable named sample stops', () async {
    final catalog = await TransitRepository().loadSakay();
    expect(catalog.routes, hasLength(1717));
    expect(
      catalog.routes.where((r) => r.mode == 'jeepney_reference').length,
      1522,
    );
    expect(
      catalog.routes.where((r) => r.mode == 'road_transit_unclassified').length,
      191,
    );
    expect(catalog.routes.where((r) => r.mode == 'rail_reference').length, 4);
    expect(catalog.stops, hasLength(4857));
    final route = catalog.routes.firstWhere((route) => route.stops.isNotEmpty);
    expect(route.matches(route.stops.first.name.toUpperCase()), isTrue);
    expect(catalog.routesAt(route.stops.first.id), contains(route));
    expect(catalog.licenseUrl, contains('LICENSE.md'));
  });

  test('Historical parser preserves missing coordinates but rejects operational promotions', () {
    final raw = {
      'schema_version': 1,
      'status': 'historical_reference_only',
      'source': 'Synthetic fixture',
      'source_url': 'https://fixture.example',
      'license_url': 'https://fixture.example/license',
      'routes': [
        {
          'id': 'r1',
          'name': 'Old route',
          'mode': 'jeepney_reference',
          'historical_only': true,
          'validated_current_operation': false,
          'ordered_stops_from_one_sample_trip': [
            {
              'stop_id': 's1',
              'name': 'Unknown position',
              'sequence': 1,
              'lat': null,
              'lon': null,
            },
          ],
        },
      ],
    };
    final catalog = SakayHistoricalCatalog.fromJsonString(jsonEncode(raw));
    expect(catalog.routes.single.stops.single.latitude, isNull);
    (raw['routes'] as List).first['validated_current_operation'] = true;
    expect(
      () => SakayHistoricalCatalog.fromJsonString(jsonEncode(raw)),
      throwsFormatException,
    );
  });

  test('Only explicitly reviewed coordinate provenance enables geographic references', () async {
    expect(await TransitRepository().loadReviewedPoints(), isEmpty);
    final point = ReviewedTransitPoint.fromJson({
      'latitude': 14.6,
      'longitude': 121,
      'source_url': 'https://fixture.example/location',
      'reviewed_on': '2026-11-08',
    });
    expect(point.point.latitude, 14.6);
    expect(
      () => ReviewedTransitPoint.fromJson({
        'latitude': 100,
        'longitude': 121,
        'source_url': '',
        'reviewed_on': 'bad',
      }),
      throwsFormatException,
    );
  });

  test('Future backend evidence needs a current date, source, status and boarding verification', () async {
    final now = DateTime.utc(2026, 11, 8);
    final backend = _EvidenceSource();
    final repository = TransitRepository(operatingRoutes: backend);
    OperatingRouteEvidence evidence({
      String status = 'independently_verified_operating',
      bool boarding = true,
      DateTime? until,
    }) => OperatingRouteEvidence(
      routeId: 'r1',
      sourceUrl: 'https://fixture.example/current-verification',
      validatedAt: now.subtract(const Duration(days: 1)),
      validUntil: until ?? now.add(const Duration(days: 1)),
      operatingStatus: status,
      boardingVerified: boarding,
      alightingVerified: true,
    );
    expect(await repository.currentEvidence('r1', now), isNull);
    backend.evidence = evidence(status: 'historical_reference_only');
    expect(await repository.currentEvidence('r1', now), isNull);
    backend.evidence = evidence(boarding: false);
    expect(await repository.currentEvidence('r1', now), isNull);
    backend.evidence = evidence(until: now);
    expect(await repository.currentEvidence('r1', now), isNull);
    backend.evidence = evidence();
    expect(await repository.currentEvidence('r1', now), isNotNull);
    expect(await repository.currentEvidence('different-route', now), isNull);
    backend.fail = true;
    expect(await repository.currentEvidence('r1', now), isNull);
  });
}
