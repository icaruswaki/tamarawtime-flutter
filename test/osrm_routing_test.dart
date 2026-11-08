import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/commute.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/journey_service.dart';
import 'package:tamaraw_time/src/journey_widgets.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/punctuality_overview.dart';
import 'package:tamaraw_time/src/routing.dart';
import 'package:tamaraw_time/src/theme.dart';

import 'support/journey_fixture.dart';
import 'support/osrm_fixture.dart';

const origin = LatLng(14.6, 121), destination = LatLng(14.6043, 120.9884);

class DelayedTransitProvider implements JourneyProvider {
  final transit = Completer<List<JourneyOption>>();
  final road = JourneyService(
    null,
    road: (from, to, mode) async {
      if (mode == 'Walking') throw StateError('Walking provider unavailable');
      return RoutePlan.fromOsrm(osrmFixture());
    },
  );

  @override
  Future<List<JourneyOption>> fetch(JourneyQuery query) =>
      query.mode == 'Transit' ? transit.future : road.fetch(query);
}

void main() {
  test(
    'OSRM numeric seconds/meters retain precision and decode GeoJSON order',
    () async {
      final requests = <Uri>[];
      final route = await http.runWithClient(
        () => Routing.road(origin, destination, 'Driving'),
        () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(jsonEncode(osrmFixture()), 200);
        }),
      );
      expect(requests.single.host, 'routing.openstreetmap.de');
      expect(
        requests.single.path,
        startsWith('/routed-car/route/v1/driving/121.0,14.6;'),
      );
      expect(requests.single.queryParameters['geometries'], 'geojson');
      expect(route.duration.inMicroseconds / 1e6, closeTo(810.9, 0.000001));
      expect(durationLabel(route.duration), '13 min 31 sec');
      expect(route.kilometers, closeTo(8.0852, 0.000001));
      expect(route.points, [origin, destination]);
      final adjusted = drivingAdjustedDuration(route.duration, const {});
      expect(adjusted.inMicroseconds / 1e6, closeTo(2610.9, 0.000001));
      expect(durationLabel(adjusted), '43 min 31 sec');
      expect(route.duration.inMilliseconds, 810900);
    },
  );

  test(
    'OSRM accepts integer numbers and rejects missing/provider-mismatched data',
    () {
      final route = RoutePlan.fromOsrm(
        osrmFixture(duration: 810, distance: 8085),
      );
      expect(route.duration, const Duration(seconds: 810));
      expect(route.kilometers, 8.085);
      for (final body in [
        {'code': 'NoRoute', 'routes': []},
        {
          'code': 'Ok',
          'trip': {
            'summary': {'time': 810.9},
          },
        },
        osrmFixture()..['routes'][0]['duration'] = '810.9s',
        osrmFixture()..['routes'][0].remove('duration'),
        osrmFixture(duration: double.nan),
        osrmFixture(distance: -1),
      ]) {
        expect(() => RoutePlan.fromOsrm(body), throwsFormatException);
      }
    },
  );

  test('Driving publishes before transit completes and survives transit/walking failure', () async {
    final provider = DelayedTransitProvider();
    final controller = JourneyController(provider: provider);
    addTearDown(controller.dispose);
    configure(controller);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final request = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(controller.loading, isTrue);
    expect(controller.pendingModes, {'Transit'});
    expect(controller.drivingEstimate!.duration.inMilliseconds, 810900);
    expect(
      controller.drivingEstimate!.steps.single.duration!.inMilliseconds,
      810900,
    );
    expect(controller.drivingEstimate!.points, [origin, destination]);
    expect(controller.walkingEstimate, isNull);
    expect(controller.selected, isNull);
    expect(notifications, greaterThan(1));
    provider.transit.completeError(StateError('Transit unavailable'));
    await request;
    expect(controller.loading, isFalse);
    expect(controller.options, isEmpty);
    expect(controller.mode, 'Transit');
    expect(controller.message, 'Public transit estimate unavailable.');
    expect(controller.drivingEstimate!.kilometers, closeTo(8.0852, 0.000001));
    expect(controller.drivingEstimate!.duration.inMilliseconds, 810900);
    controller.configure(
      destination: campusPoints['FEU Diliman']!,
      label: 'Diliman',
      mode: 'Transit',
      autoRefresh: false,
    );
    expect(controller.drivingEstimate, isNull);
    expect(controller.walkingEstimate, isNull);
  });

  testWidgets(
    'Actual OSRM response reaches dashboard, commute cards and driving map without transit',
    (tester) async {
      final requests = <Uri>[];
      final controller = JourneyController(provider: JourneyService(null));
      final planner = Planner(null, journey: controller)..local = true;
      configure(controller);
      await http.runWithClient(
        controller.refresh,
        () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(jsonEncode(osrmFixture()), 200);
        }),
      );
      expect(
        requests.map((uri) => uri.path),
        containsAll([startsWith('/routed-foot/'), startsWith('/routed-car/')]),
      );
      expect(controller.selected, isNull);
      expect(controller.walkingEstimate!.duration.inMilliseconds, 810900);

      Widget app(Widget child) => MaterialApp(
        theme: tamarawTheme('forest'),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );
      void checkEstimates() {
        expect(find.text('Driving alternative'), findsOneWidget);
        expect(find.text('Walking estimate'), findsOneWidget);
        expect(
          find.textContaining('Base OSRM: 13 min 31 sec · 8.0852 km'),
          findsOneWidget,
        );
        expect(
          find.textContaining('With traffic allowance: 43 min 31 sec'),
          findsOneWidget,
        );
        expect(
          find.textContaining('not real-time traffic data'),
          findsOneWidget,
        );
        expect(find.text(liveEstimatesUnavailable), findsNothing);
        expect(controller.selected, isNull);
      }

      await tester.pumpWidget(
        app(PunctualityOverview(planner: planner, onCommute: () {})),
      );
      await tester.pumpAndSettle();
      checkEstimates();
      planner.settings['trafficBufferMinutes'] = 15;
      await tester.pumpWidget(
        app(PunctualityOverview(planner: planner, onCommute: () {})),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('With traffic allowance: 28 min 31 sec'),
        findsOneWidget,
      );
      expect(controller.walkingEstimate!.duration.inMilliseconds, 810900);
      planner.settings['trafficBufferMinutes'] = 30;

      await tester.pumpWidget(
        app(Commute(planner: planner, onSave: () async {})),
      );
      await tester.pumpAndSettle();
      checkEstimates();
      expect(
        find.textContaining('Public transit estimate unavailable.'),
        findsWidgets,
      );
      await tester.ensureVisible(find.text('Driving alternative'));
      await tester.tap(find.text('Driving alternative'));
      await tester.pumpAndSettle();
      final map = tester.widget<FlutterMap>(
        find.byKey(const ValueKey('commute-map')),
      );
      expect(
        map.children
            .whereType<PolylineLayer>()
            .expand((layer) => layer.polylines)
            .map((line) => line.points),
        contains(orderedEquals([origin, destination])),
      );
      expect(controller.selected, isNull);
      expect(tester.takeException(), isNull);

      await http.runWithClient(
        () async {
          await tester.ensureVisible(find.text('Find public transit'));
          await tester.tap(find.text('Find public transit'));
          await tester.pumpAndSettle();
          final sheet = find.byKey(const ValueKey('journey-details-sheet'));
          expect(sheet, findsOneWidget);
          expect(find.text('Travel estimates'), findsOneWidget);
          checkEstimates();
          await tester.drag(
            find.text('Travel estimates'),
            const Offset(0, -350),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Driving alternative'));
          await tester.tap(find.text('Driving alternative'));
          await tester.pumpAndSettle();
          final expanded = tester.widget<FlutterMap>(
            find.byKey(const ValueKey('expanded-route-map')),
          );
          expect(
            expanded.children
                .whereType<PolylineLayer>()
                .expand((layer) => layer.polylines)
                .map((line) => line.points),
            contains(orderedEquals([origin, destination])),
          );
          expect(controller.selected, isNull);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Back to commute planner'));
          await tester.pumpAndSettle();
        },
        () => MockClient(
          (request) async => request.url.host == 'routing.openstreetmap.de'
              ? http.Response(jsonEncode(osrmFixture()), 200)
              : http.Response('', 400),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );
}
