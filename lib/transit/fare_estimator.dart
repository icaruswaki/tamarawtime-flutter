import 'dart:convert';

import '../src/journey.dart';
import 'fare_calculator.dart';
import 'rail_fares.dart';

/// Independent current service verification, separate from historical GTFS.
/// A generic BUS vehicle type or a matching route name is insufficient.
class VerifiedFareService {
  const VerifiedFareService({
    required this.lineUri,
    required this.agencyUri,
    required this.vehicle,
    required this.fareMode,
    required this.evidenceUrl,
    required this.verifiedAt,
    required this.validUntil,
  });

  final String lineUri, agencyUri, vehicle, fareMode, evidenceUrl;
  final DateTime verifiedAt, validUntil;

  bool get compatibleVehicle => switch (fareMode) {
    'ordinary_city_bus' || 'aircon_city_bus' => vehicle == 'BUS',
    'traditional_jeepney' ||
    'modern_jeepney' => {'BUS', 'OTHER', 'SHARE_TAXI'}.contains(vehicle),
    _ => false,
  };

  factory VerifiedFareService.fromJson(Map<String, dynamic> json) {
    final service = VerifiedFareService(
      lineUri: json['line_uri'] as String,
      agencyUri: json['agency_uri'] as String,
      vehicle: json['provider_vehicle'] as String,
      fareMode: json['fare_mode'] as String,
      evidenceUrl: json['evidence_url'] as String,
      verifiedAt: DateTime.parse(json['verified_at'] as String),
      validUntil: DateTime.parse(json['valid_until'] as String),
    );
    if (json['status'] != 'verified_current' ||
        ![service.lineUri, service.agencyUri, service.evidenceUrl].every((url) {
          final uri = Uri.tryParse(url);
          return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
        }) ||
        !service.validUntil.isAfter(service.verifiedAt) ||
        !service.compatibleVehicle ||
        !service.verifiedAt.isUtc ||
        !service.validUntil.isUtc) {
      throw const FormatException('Service verification is incomplete');
    }
    return service;
  }

  bool matches(JourneyStep step, DateTime now) =>
      compatibleVehicle &&
      !now.isBefore(verifiedAt) &&
      now.isBefore(validUntil) &&
      step.lineUri == lineUri &&
      step.agencyUris.contains(agencyUri) &&
      step.vehicle == vehicle;
}

class EstimatedFareLeg {
  const EstimatedFareLeg(this.step, this.service, this.estimate, {this.rail});
  final JourneyStep step;
  final VerifiedFareService? service;
  final ReviewedRailFare? rail;
  String get evidenceUrl => rail?.review.source ?? service!.evidenceUrl;
  final FareEstimate estimate;
}

class JourneyFareEstimate {
  const JourneyFareEstimate(this.legs, this.unavailableLegs, {this.reason});
  final List<EstimatedFareLeg> legs;
  final int unavailableLegs;
  final String? reason;
  bool get complete => legs.isNotEmpty && unavailableLegs == 0;
  double get regular => legs.fold(0, (sum, leg) => sum + leg.estimate.fullFare);
  double get student =>
      legs.fold(0, (sum, leg) => sum + leg.estimate.studentFare);
}

class FareEstimatorService {
  const FareEstimatorService(
    this.calculator,
    this.services, {
    this.railFares = const [],
  });
  final FareCalculator calculator;
  final List<VerifiedFareService> services;
  final List<ReviewedRailFare> railFares;

  static List<VerifiedFareService> parseServices(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return List.unmodifiable(
      (json['services'] as List).map(
        (raw) =>
            VerifiedFareService.fromJson(Map<String, dynamic>.from(raw as Map)),
      ),
    );
  }

  JourneyFareEstimate estimate(
    JourneyOption? journey, {
    required DateTime now,
  }) {
    if (journey == null ||
        !journey.freshAt(now) ||
        now.isBefore(journey.updatedAt)) {
      return const JourneyFareEstimate(
        [],
        0,
        reason: 'Find or refresh a route first.',
      );
    }
    final effective = DateTime.parse(calculator.effectiveDate);
    final philippineDate = now.toUtc().add(const Duration(hours: 8));
    if (DateTime.utc(
      philippineDate.year,
      philippineDate.month,
      philippineDate.day,
    ).isBefore(DateTime.utc(effective.year, effective.month, effective.day))) {
      return const JourneyFareEstimate(
        [],
        0,
        reason: 'Fare reference is not yet effective.',
      );
    }
    final legs = <EstimatedFareLeg>[];
    var missing = 0;
    for (final step in journey.steps.where((step) => !step.walking)) {
      final railMatches = railFares
          .where(
            (fare) =>
                fare.quote(step, now) != null &&
                fare.quote(step, step.departure ?? journey.departure ?? now) !=
                    null,
          )
          .toList();
      if (railMatches.length == 1) {
        final rail = railMatches.single,
            price = railMatches.single.quote(step, now)!;
        legs.add(
          EstimatedFareLeg(
            step,
            null,
            FareEstimate(
              price,
              price,
              'Published stored-value fare; no extra student discount inferred.',
            ),
            rail: rail,
          ),
        );
        continue;
      }
      final matches = services
          .where(
            (service) =>
                service.matches(step, now) &&
                service.matches(
                  step,
                  step.departure ?? journey.departure ?? now,
                ),
          )
          .toList();
      final meters = step.meters;
      // Use the provider's traveled distance for THIS ride. Never use total-trip
      // distance, polyline length, GPS straight lines or historical stop shapes.
      final fare =
          {
                JourneySource.google,
                JourneySource.openTripPlanner,
                JourneySource.localGraph,
              }.contains(journey.source) &&
              step.transit &&
              matches.length == 1 &&
              meters != null &&
              meters.isFinite &&
              meters > 0
          ? calculator.estimate(matches.single.fareMode, meters / 1000)
          : null;
      if (fare == null) {
        missing++;
      } else {
        legs.add(EstimatedFareLeg(step, matches.single, fare));
      }
    }
    return JourneyFareEstimate(
      List.unmodifiable(legs),
      missing,
      reason: legs.isEmpty
          ? 'A verified vehicle category and provider distance for each ride are required.'
          : null,
    );
  }
}
