import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/transit/departure_calculator.dart';
import 'package:tamaraw_time/transit/fare_calculator.dart';
import 'package:tamaraw_time/transit/fare_estimator.dart';
import 'package:tamaraw_time/transit/transit_models.dart';
import 'package:tamaraw_time/transit/transit_repository.dart';

import 'support/transit_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fares = referenceFares();
  final now = DateTime.utc(2026, 11, 8, 1);
  final estimator = verifiedEstimator(now);

  test('Rail, intercity buses and undated verification cannot authorize covered fare modes', () {
    for (final vehicle in ['SUBWAY', 'INTERCITY_BUS', 'FERRY']) {
      expect(
        () => VerifiedFareService.fromJson({
          ...verifiedServiceJson(now),
          'provider_vehicle': vehicle,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => VerifiedFareService.fromJson({
        ...verifiedServiceJson(now),
        'verified_at': '2026-11-07T00:00:00',
      }),
      throwsFormatException,
    );
  });

  test(
    'Service verification must remain valid at the actual ride departure',
    () {
      final result = estimator.estimate(
        fareJourney(
          now,
          steps: [
            JourneyStep(
              mode: 'TRANSIT',
              vehicle: 'BUS',
              lineUri: 'https://fixture.example/service/1',
              agencyUris: const ['https://fixture.example/operator'],
              meters: 6000,
              departure: now.add(const Duration(days: 2)),
            ),
          ],
        ),
        now: now,
      );
      expect(result.legs, isEmpty);
    },
  );

  test('September 28 reference covers all four base distances and prices', () {
    final cases = {
      'traditional_jeepney': (4.0, 14.0, 11.25),
      'modern_jeepney': (4.0, 17.0, 13.5),
      'ordinary_city_bus': (5.0, 15.0, 12.0),
      'aircon_city_bus': (5.0, 18.0, 14.5),
    };
    expect(fares.effectiveDate, '2026-09-28');
    for (final entry in cases.entries) {
      for (final km in [0.001, entry.value.$1 - 0.001, entry.value.$1]) {
        final result = fares.estimate(entry.key, km)!;
        expect(result.fullFare, entry.value.$2);
        expect(result.studentFare, entry.value.$3);
        expect(result.disclaimer, contains('Reference estimate'));
      }
    }
  });

  test(
    'Fractional traveled kilometers use the correct rate and quarter rounding',
    () {
      expect(fares.estimate('traditional_jeepney', 6)!.fullFare, 18);
      expect(fares.estimate('traditional_jeepney', 6)!.studentFare, 14.5);
      expect(fares.estimate('modern_jeepney', 6.5)!.fullFare, 23);
      expect(fares.estimate('ordinary_city_bus', 6)!.fullFare, 17.5);
      expect(fares.estimate('aircon_city_bus', 6)!.fullFare, 21);
      expect(fares.estimate('ordinary_city_bus', 5.001)!.fullFare, 15);
    },
  );

  test('Unknown categories and invalid distances never produce fares', () {
    for (final mode in [
      'BUS',
      'Jeepney',
      'train',
      'UV Express',
      'Walking',
      'Driving',
      'MRT-3',
    ]) {
      expect(fares.estimate(mode, 6), isNull);
    }
    for (final distance in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      -double.infinity,
      double.maxFinite,
    ]) {
      expect(fares.estimate('traditional_jeepney', distance), isNull);
    }
  });

  test('Malformed reference configuration is rejected', () {
    final json = jsonDecode(
      File('assets/transit/ltfrb_fares_2026_09_28.json').readAsStringSync(),
    );
    json['modes']['ordinary_city_bus']['base_km'] = -1;
    expect(
      () => FareCalculator.fromJsonString(jsonEncode(json)),
      throwsFormatException,
    );
    json['modes']['ordinary_city_bus']['base_km'] = 5;
    json['discount']['student'] = 1.5;
    expect(
      () => FareCalculator.fromJsonString(jsonEncode(json)),
      throwsFormatException,
    );
  });

  test('Verified ride uses its traveled distance rather than total journey distance', () {
    final result = estimator.estimate(fareJourney(now), now: now);
    expect(result.complete, isTrue);
    expect(result.regular, 17.5); // 6 km ride, not the 100 km journey field.
    expect(result.student, 14);
  });

  test('Transfers charge each verified ride separately and ignore walking distance', () {
    final result = estimator.estimate(
      fareJourney(
        now,
        steps: [
          const JourneyStep(mode: 'WALK', meters: 20000),
          verifiedBus(meters: 3000),
          verifiedBus(meters: 6000),
        ],
      ),
      now: now,
    );
    expect(result.complete, isTrue);
    expect(result.regular, 32.5);
    expect(result.student, 26);
  });

  test('Unsupported rides produce a partial subtotal rather than a full trip total', () {
    final result = estimator.estimate(
      fareJourney(
        now,
        steps: [
          verifiedBus(),
          const JourneyStep(mode: 'TRANSIT', vehicle: 'SUBWAY', meters: 4000),
        ],
      ),
      now: now,
    );
    expect(result.complete, isFalse);
    expect(result.legs, hasLength(1));
    expect(result.unavailableLegs, 1);
  });

  test(
    'Selected mode and generic BUS do not prove a regulated fare category',
    () {
      final result = estimator.estimate(
        fareJourney(
          now,
          steps: [
            const JourneyStep(
              mode: 'TRANSIT',
              vehicle: 'BUS',
              lineName: 'ordinary_city_bus',
              meters: 6000,
            ),
          ],
        ),
        now: now,
      );
      expect(result.legs, isEmpty);
      expect(result.complete, isFalse);
    },
  );

  test('Missing, invalid ride distances never use total or GPS distance', () {
    for (final meters in [null, 0.0, -1.0, double.nan, double.infinity]) {
      expect(
        estimator
            .estimate(
              fareJourney(now, steps: [verifiedBus(meters: meters)]),
              now: now,
            )
            .legs,
        isEmpty,
      );
    }
  });

  test(
    'OSM discovery, stale routes and future-dated responses cannot price rides',
    () {
      expect(
        estimator
            .estimate(
              fareJourney(now, source: JourneySource.openStreetMap),
              now: now,
            )
            .legs,
        isEmpty,
      );
      expect(
        estimator
            .estimate(
              fareJourney(now.subtract(const Duration(minutes: 6))),
              now: now,
            )
            .legs,
        isEmpty,
      );
      expect(
        estimator
            .estimate(
              fareJourney(now.add(const Duration(minutes: 1))),
              now: now,
            )
            .legs,
        isEmpty,
      );
      expect(estimator.estimate(null, now: now).legs, isEmpty);
    },
  );

  test(
    'Expired or ambiguous verification and mismatched agency fail closed',
    () {
      final expired = FareEstimatorService(fares, [
        VerifiedFareService.fromJson({
          ...verifiedServiceJson(now),
          'valid_until': now.toIso8601String(),
        }),
      ]);
      expect(expired.estimate(fareJourney(now), now: now).legs, isEmpty);
      final ambiguous = FareEstimatorService(fares, [
        ...estimator.services,
        ...estimator.services,
      ]);
      expect(ambiguous.estimate(fareJourney(now), now: now).legs, isEmpty);
      final mismatch = FareEstimatorService(fares, [
        VerifiedFareService.fromJson({
          ...verifiedServiceJson(now),
          'agency_uri': 'https://fixture.example/different-operator',
        }),
      ]);
      expect(mismatch.estimate(fareJourney(now), now: now).legs, isEmpty);
    },
  );

  test(
    'Historical service verification cannot authorize current fare estimates',
    () {
      expect(
        () => FareEstimatorService.parseServices(
          jsonEncode({
            'services': [
              {...verifiedServiceJson(now), 'status': 'unverified_historical'},
            ],
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Reference fares are not applied before their effective Philippine date',
    () {
      final earlier = DateTime.utc(2026, 9, 27, 15, 59);
      final service = verifiedEstimator(earlier);
      expect(
        service.estimate(fareJourney(earlier), now: earlier).legs,
        isEmpty,
      );
      final effective = DateTime.utc(2026, 9, 27, 16);
      expect(
        service.estimate(fareJourney(effective), now: effective).complete,
        isTrue,
      );
    },
  );

  test('Asset repository loads the intentionally empty catalog and service registry', () async {
    final repository = TransitRepository();
    expect((await repository.loadCatalog()).routes, isEmpty);
    expect((await repository.loadEstimator()).services, isEmpty);
    expect((await repository.loadFares()).effectiveDate, '2026-09-28');
  });

  test('Departure separates real travel duration, arrival buffer and preparation across midnight', () {
    final result = calculateDeparture(
      classStart: DateTime.utc(2026, 11, 9, 0, 15),
      travelEstimate: const Duration(minutes: 35),
      arrivalBuffer: const Duration(minutes: 15),
      preparationDuration: const Duration(minutes: 20),
    )!;
    expect(result.leaveAt, DateTime.utc(2026, 11, 8, 23, 25));
    expect(result.prepareAt, DateTime.utc(2026, 11, 8, 23, 5));
    expect(result.estimatedArrival, DateTime.utc(2026, 11, 9));
  });

  test('Missing and invalid timing inputs do not produce departure recommendations', () {
    for (final travel in [null, Duration.zero, const Duration(minutes: -1)]) {
      expect(
        calculateDeparture(classStart: now, travelEstimate: travel),
        isNull,
      );
    }
    expect(
      calculateDeparture(
        classStart: now,
        travelEstimate: const Duration(minutes: 10),
        preparationDuration: const Duration(minutes: -1),
      ),
      isNull,
    );
    expect(
      calculateDeparture(
        classStart: now,
        travelEstimate: const Duration(minutes: 10),
        arrivalBuffer: const Duration(minutes: -1),
      ),
      isNull,
    );
  });

  test(
    'Historical parser preserves sequence, never upgrades historical flags',
    () {
      final catalog = TransitCatalog.fromJsonString(
        jsonEncode({
          'data_status': 'unverified_historical',
          'source': 'Synthetic test fixture',
          'routes': [
            {
              'id': 'r1',
              'name': 'Historic reference',
              'mode': 'bus',
              'historical': false,
            },
          ],
          'stops': [
            {'id': 's1', 'name': 'First', 'lat': 14.6, 'lon': 121},
            {'id': 's2', 'name': 'Second', 'lat': 14.61, 'lon': 121.01},
          ],
          'route_stops': {
            'r1': ['s2', 's1'],
          },
        }),
      );
      expect(catalog.routes.single.historical, isTrue);
      expect(catalog.routeStops['r1'], ['s2', 's1']);
      expect(catalog.routesServingStop('s2').single.id, 'r1');
    },
  );

  test('Catalog parser rejects live claims, invalid positions and missing stop references', () {
    expect(
      () => TransitCatalog.fromJsonString('{"data_status":"verified_live"}'),
      throwsFormatException,
    );
    expect(
      () => TransitCatalog.fromJsonString(
        jsonEncode({
          'routes': [],
          'stops': [
            {'id': 's1', 'name': 'Bad', 'lat': 100, 'lon': 121},
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => TransitCatalog.fromJsonString(
        jsonEncode({
          'routes': [
            {'id': 'r', 'name': 'Historic', 'mode': 'bus'},
          ],
          'stops': [],
          'route_stops': {
            'r': ['missing'],
          },
        }),
      ),
      throwsFormatException,
    );
  });
}
