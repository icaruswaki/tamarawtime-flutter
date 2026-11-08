import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'fare_estimator.dart';
import 'fare_calculator.dart';
import 'transit_models.dart';
import 'rail_reference_repository.dart';
import 'sakay_reference.dart';
import 'operating_route_source.dart';
import 'rail_fares.dart';

/// Call from the existing app's DI/state layer; no screens are overwritten.
class TransitRepository {
  TransitRepository({
    this.operatingRoutes = const UnavailableOperatingRouteSource(),
    RailReferenceRepository? rail,
  }) : rail = rail ?? RailReferenceRepository();
  final OperatingRouteSource operatingRoutes;
  final RailReferenceRepository rail;
  Future<SakayHistoricalCatalog>? _sakay;
  Future<Map<String, ReviewedTransitPoint>>? _reviewedPoints;
  Future<SakayHistoricalCatalog> loadSakay() => _sakay ??= _loadSakay();
  Future<SakayHistoricalCatalog> _loadSakay() async =>
      SakayHistoricalCatalog.fromJsonString(
        await rootBundle.loadString('assets/transit/sakay_historical.json'),
      );
  Future<Map<String, ReviewedTransitPoint>> loadReviewedPoints() =>
      _reviewedPoints ??= _loadPoints();
  Future<Map<String, ReviewedTransitPoint>> _loadPoints() async {
    final json = jsonDecode(
      await rootBundle.loadString(
        'assets/transit/reviewed_transit_points.json',
      ),
    ) as Map;
    return Map.unmodifiable(
      (json['points'] as Map<String, dynamic>).map(
        (key, raw) => MapEntry(
          key,
          ReviewedTransitPoint.fromJson(Map<String, dynamic>.from(raw as Map)),
        ),
      ),
    );
  }

  Future<OperatingRouteEvidence?> currentEvidence(
    String routeId,
    DateTime now,
  ) async {
    try {
      final evidence = await operatingRoutes.lookup(routeId);
      return evidence != null && evidence.validFor(routeId, now)
          ? evidence
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<TransitCatalog>? _catalog;
  Future<FareEstimatorService>? _estimator;

  Future<TransitCatalog> loadCatalog() => _catalog ??= _loadCatalog();
  Future<TransitCatalog> _loadCatalog() async => TransitCatalog.fromJsonString(
    await rootBundle.loadString('assets/transit/transit_catalog.json'),
  );

  Future<FareEstimatorService> loadEstimator() =>
      _estimator ??= _loadEstimator();
  Future<FareEstimatorService> _loadEstimator() async => FareEstimatorService(
    await loadFares(),
    FareEstimatorService.parseServices(
      await rootBundle.loadString('assets/transit/verified_fare_services.json'),
    ),
    railFares: ReviewedRailFare.parse(
      await rootBundle.loadString('assets/transit/rail_fares_reviewed.json'),
    ),
  );

  Future<FareCalculator> loadFares() async => FareCalculator.fromJsonString(
    await rootBundle.loadString('assets/transit/ltfrb_fares_2026_09_28.json'),
  );
}
