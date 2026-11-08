// Opt-in network integration, never required for deterministic widget tests.
// flutter test --dart-define=LIVE_LOCAL_TRANSIT=true test/local_transit_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/routing.dart';
import 'package:tamaraw_time/transit/local_transit_provider.dart';

void main() {
  const enabled = bool.fromEnvironment('LIVE_LOCAL_TRANSIT');
  // Construct before the widget binding's deliberate HTTP override.
  final client = enabled ? IOClient(HttpClient()) : null;
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Live OSRM access plus bundled rails returns connected instructions',
    () async {
      addTearDown(client!.close);
      final graph = await LocalTransitProvider.loadBundledGraph();
      final station = graph.byId['LRT-2:Katipunan']!;
      final origin = LatLng(
        station.point.latitude + .0003,
        station.point.longitude,
      );
      final requests = <Map<String, Object>>[];
      final provider = LocalTransitProvider(
        load: () async => graph,
        walk: (from, to, mode) async {
          final response = await client
              .get(
                Uri.parse(
                  'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
                  '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
                  '?overview=full&geometries=geojson',
                ),
              )
              .timeout(const Duration(seconds: 20));
          expect(response.statusCode, 200);
          final plan = RoutePlan.fromOsrm(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
          requests.add({
            'from': [from.latitude, from.longitude],
            'to': [to.latitude, to.longitude],
            'seconds': plan.duration.inMilliseconds / 1000,
            'meters': plan.meters,
            'geometryPoints': plan.points.length,
          });
          return plan;
        },
      );
      final options = await provider.fetch(
        JourneyQuery(
          origin: origin,
          destination: campusPoints['FEU Tech']!,
          mode: 'Transit',
        ),
      );
      expect(options, isNotEmpty, reason: provider.transitUnavailableReason);
      expect(options.length, lessThanOrEqualTo(3));
      for (final option in options) {
        expect(option.source, JourneySource.localGraph);
        expect(option.hasDuration, isFalse);
        expect(option.steps.first.walking, isTrue);
        expect(option.steps.last.walking, isTrue);
        expect(option.steps.where((s) => s.transit), isNotEmpty);
        expect(option.steps.every((s) => s.points.length >= 2), isTrue);
      }
      final evidence = {
        'testedAt': DateTime.now().toUtc().toIso8601String(),
        'endpoint':
            'https://routing.openstreetmap.de/routed-foot/route/v1/driving/',
        'requests': requests,
        'journeys': [
          for (final o in options)
            {
              'id': o.id,
              'totalEta': null,
              'transfers': o.transfers,
              'steps': [
                for (final s in o.steps)
                  {
                    'mode': s.mode,
                    'line': s.lineName,
                    'board': s.boardingStop,
                    'alight': s.alightingStop,
                    'direction': s.headsign,
                    'geometryPoints': s.points.length,
                  },
              ],
            },
        ],
      };
      final output = File('.dart_tool/local_graph/live-probe.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert(evidence),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
