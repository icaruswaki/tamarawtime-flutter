import 'dart:io';

import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/transit/fare_calculator.dart';
import 'package:tamaraw_time/transit/fare_estimator.dart';
import 'package:tamaraw_time/transit/transit_models.dart';
import 'package:tamaraw_time/transit/transit_repository.dart';

FareCalculator referenceFares() => FareCalculator.fromJsonString(
  File('assets/transit/ltfrb_fares_2026_09_28.json').readAsStringSync(),
);

Map<String, dynamic> verifiedServiceJson(DateTime now) => {
  'status': 'verified_current',
  'line_uri': 'https://fixture.example/service/1',
  'agency_uri': 'https://fixture.example/operator',
  'provider_vehicle': 'BUS',
  'fare_mode': 'ordinary_city_bus',
  'evidence_url': 'https://fixture.example/current-service-classification',
  'verified_at': now.subtract(const Duration(days: 1)).toIso8601String(),
  'valid_until': now.add(const Duration(days: 1)).toIso8601String(),
};

FareEstimatorService verifiedEstimator(DateTime now) => FareEstimatorService(
  referenceFares(),
  [VerifiedFareService.fromJson(verifiedServiceJson(now))],
);

JourneyStep verifiedBus({double? meters = 6000}) => JourneyStep(
  mode: 'TRANSIT',
  vehicle: 'BUS',
  lineName: 'Fixture ordinary city bus',
  lineUri: 'https://fixture.example/service/1',
  agencyUris: const ['https://fixture.example/operator'],
  meters: meters,
);

JourneyOption fareJourney(
  DateTime now, {
  List<JourneyStep>? steps,
  JourneySource source = JourneySource.google,
}) => JourneyOption(
  id: 'fixture',
  duration: const Duration(minutes: 30),
  meters: 100000,
  points: const [],
  steps: steps ?? [verifiedBus()],
  updatedAt: now,
  departure: now.add(const Duration(minutes: 2)),
  arrival: now.add(const Duration(minutes: 32)),
  source: source,
);

class FixtureTransitRepository extends TransitRepository {
  FixtureTransitRepository(
    FareEstimatorService estimator, {
    TransitCatalog? catalog,
  }) : _estimator = Future.value(estimator),
       _catalog = Future.value(
         catalog ?? const TransitCatalog([], [], {}, 'no_verified_live_data'),
       );
  final Future<FareEstimatorService> _estimator;
  final Future<TransitCatalog> _catalog;
  @override
  Future<FareEstimatorService> loadEstimator() => _estimator;
  @override
  Future<TransitCatalog> loadCatalog() => _catalog;
}
