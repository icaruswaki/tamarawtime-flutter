import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

import 'journey.dart';
import 'map_configuration.dart';
import 'routing.dart';

abstract interface class JourneyProvider {
  Future<List<JourneyOption>> fetch(JourneyQuery query);
}

class JourneyService implements JourneyProvider {
  JourneyService(
    this.cloud, {
    this.road = Routing.road,
    bool Function()? googleReady,
  }) : googleReady = googleReady ?? (() => GoogleMapsSetup.available);
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
    if (!['Walking', 'Driving'].contains(query.mode)) return [];
    try {
      final route = await road(query.origin, query.destination, query.mode);
      return [
        JourneyOption(
          id: 'osm-road',
          duration: Duration(minutes: route.minutes),
          meters: route.meters,
          points: route.points,
          updatedAt: DateTime.now().toUtc(),
          source: JourneySource.openStreetMap,
          steps: [
            JourneyStep(
              mode: query.mode == 'Walking' ? 'WALK' : 'DRIVE',
              duration: Duration(minutes: route.minutes),
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
