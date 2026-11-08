import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

import 'journey.dart';
import 'map_configuration.dart';
import 'routing.dart';
import '../transit/otp_journey_provider.dart';
import '../transit/local_transit_provider.dart';

export 'journey.dart' show JourneyProvider;

class JourneyService implements JourneyProvider, TransitAvailability {
  JourneyService(
    this.cloud, {
    this.road = Routing.road,
    bool Function()? googleReady,
    OtpJourneyProvider? transit,
    JourneyProvider? local,
  }) : googleReady = googleReady ?? (() => GoogleMapsSetup.available),
       transit = transit ?? OtpJourneyProvider.fromEnvironment(),
       local = local ?? LocalTransitProvider(walk: road);
  final JourneyProvider local;
  String? _transitReason;
  final OtpJourneyProvider transit;
  @override
  String? get transitUnavailableReason => _transitReason;
  final SupabaseClient? cloud;
  final bool Function() googleReady;
  final Future<RoutePlan> Function(LatLng, LatLng, String) road;
  @override
  Future<List<JourneyOption>> fetch(JourneyQuery query) async {
    // Google requests only go through the authenticated backend. This build has
    // no server API key, and cannot create provider ETAs without backend data.
    if (googleReady() && cloud?.auth.currentSession != null) {
      try {
        final response = await cloud!.functions
            .invoke('commute-routes', body: query.toJson())
            .timeout(const Duration(seconds: 20));
        if (response.status == 200 && response.data is Map) {
          final options = parseGoogleJourneys(
            Map<String, dynamic>.from(response.data as Map),
            requestedMode: query.mode,
            receivedAt: DateTime.now().toUtc(),
          );
          if (options.isNotEmpty) return options;
        }
      } catch (_) {
        // A road-only fallback is separately attributed, never called Google.
      }
    }
    if (!['Walking', 'Driving'].contains(query.mode)) {
      final remote = await transit.fetch(query);
      if (remote.isNotEmpty) return remote;
      final modeled = await local.fetch(query);
      _transitReason = modeled.isEmpty
          ? '${transit.unavailableReason ?? ''} ${local is TransitAvailability ? (local as TransitAvailability).transitUnavailableReason ?? '' : ''}'
                .trim()
          : null;
      return modeled;
    }
    try {
      final route = await road(query.origin, query.destination, query.mode);
      return [
        JourneyOption(
          id: 'osm-road',
          duration: route.duration,
          meters: route.meters,
          points: route.points,
          updatedAt: DateTime.now().toUtc(),
          source: JourneySource.openStreetMap,
          steps: [
            JourneyStep(
              mode: query.mode == 'Walking' ? 'WALK' : 'DRIVE',
              duration: route.duration,
              meters: route.meters,
              points: route.points,
            ),
          ],
        ),
      ];
    } catch (_) {
      return [];
    }
  }
}
