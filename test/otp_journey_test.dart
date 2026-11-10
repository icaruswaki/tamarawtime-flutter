import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/commute.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/journey_service.dart';
import 'package:tamaraw_time/src/journey_widgets.dart';
import 'package:tamaraw_time/src/routing.dart';
import 'package:tamaraw_time/src/theme.dart';
import 'package:tamaraw_time/transit/otp_journey_provider.dart';

import 'support/journey_fixture.dart';
import 'support/otp_fixture.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 1);
  test('Current OTP connection keeps access, transfers, egress and waiting in total duration', () {
    final payload = otpFixture(now);
    payload['data']['planConnection']['edges'][0]['node']['legs'][1]['legGeometry'] =
        {'points': r'_p~iF~ps|U_ulLnnqC_mqNvxq`@'};
    final option = parseOtpJourneys(payload, receivedAt: now).single;
    expect(option.duration, const Duration(minutes: 45));
    expect(
      option.steps.fold<Duration>(
        Duration.zero,
        (sum, step) => sum + step.duration!,
      ),
      const Duration(minutes: 38),
    );
    expect(option.steps.map((step) => step.mode), [
      'WALK',
      'TRANSIT',
      'WALK',
      'TRANSIT',
      'WALK',
    ]);
    expect(option.transfers, 1);
    expect(option.steps[1].headsign, 'Fixture southbound terminal');
    expect(option.steps[1].boardingStop, 'Fixture boarding station');
    expect(option.steps[1].alightingStop, 'Fixture interchange');
    expect(option.steps[1].boardingPoint, const LatLng(14.601, 121));
    expect(option.steps[1].points.first, const LatLng(38.5, -120.2));
    expect(
      option.steps.last.instruction,
      'Walk from Fixture alighting stop to FEU Tech',
    );
    expect(option.source, JourneySource.openTripPlanner);
    expect(option.sourceLabel, contains('not a live arrival prediction'));
    expect(option.fare, isNull);
    expect(option.steps[3].lineUri, 'https://fixture.example/line/Fixture Bus');
    final advice = DepartureAdvice.calculate(
      classStart: now.add(const Duration(hours: 2)),
      now: now,
      preparation: const Duration(minutes: 30),
      buffer: const Duration(minutes: 15),
      journey: option,
    );
    expect(advice.leaveAt, option.departure);
    expect(advice.arriveAt, option.arrival);
    expect(advice.travelDuration, const Duration(minutes: 45));
  });

  test('Unvalidated, stale, malformed and walk-only responses never become transit ETAs', () {
    final unvalidated = otpFixture(now)..['scheduleValidated'] = false;
    final stale = otpFixture(now)
      ..['generatedAt'] = now
          .subtract(const Duration(minutes: 6))
          .toIso8601String();
    final missing = otpFixture(now);
    missing['data']['planConnection']['edges'][0]['node']['legs'][1].remove(
      'start',
    );
    final walk = otpFixture(now);
    for (final leg
        in walk['data']['planConnection']['edges'][0]['node']['legs']) {
      leg['transitLeg'] = false;
      leg['mode'] = 'WALK';
    }
    final invalid = otpFixture(now);
    invalid['data']['planConnection']['edges'][0]['node']['duration'] = '2700s';
    for (final response in [unvalidated, stale, missing, walk, invalid]) {
      expect(parseOtpJourneys(response, receivedAt: now), isEmpty);
    }
  });

  test('Gateway adapter and shared state keep OSRM estimates when current schedules are missing', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/plan');
      expect(jsonDecode(request.body)['mode'], 'Transit');
      return http.Response(
        jsonEncode({
          'reason': 'GTFS service calendars have expired. Historical dates were not modified.',
        }),
        503,
      );
    });
    final controller = JourneyController(
      provider: JourneyService(
        null,
        local: TestProvider(),
        transit: OtpJourneyProvider(
          endpoint: Uri.parse('http://localhost:8090/plan'),
          client: client,
        ),
        road: (from, to, mode) async => RoutePlan.timed(
          [from, to],
          const Duration(milliseconds: 810900),
          8085.2,
        ),
      ),
    );
    addTearDown(controller.dispose);
    configure(controller);
    await controller.refresh();
    expect(controller.options, isEmpty);
    expect(controller.message, contains('GTFS service calendars have expired'));
    expect(controller.drivingEstimate!.duration.inMilliseconds, 810900);
    expect(controller.walkingEstimate!.duration.inMilliseconds, 810900);
  });

  test('Gateway response reaches primary state without affecting secondary road duration', () async {
    final clock = DateTime.now().toUtc();
    final client = MockClient(
      (request) async => http.Response(jsonEncode(otpFixture(clock)), 200),
    );
    final controller = JourneyController(
      provider: JourneyService(
        null,
        transit: OtpJourneyProvider(
          endpoint: Uri.parse('http://localhost:8090/plan'),
          client: client,
        ),
        road: (from, to, mode) async => RoutePlan([from, to], 14, 8085.2),
      ),
    );
    addTearDown(controller.dispose);
    configure(controller);
    await controller.refresh();
    expect(controller.selected!.source, JourneySource.openTripPlanner);
    expect(controller.selected!.transfers, 1);
    expect(controller.selected!.steps, hasLength(5));
    expect(controller.drivingEstimate!.minutes, 14);
    expect(controller.mode, 'Transit');
  });

  testWidgets(
    'OTP response reaches the Commute Planner with arrival and class departure advice',
    (tester) async {
      final clock = DateTime.now().toUtc();
      final payload = otpFixture(clock);
      // Synthetic rail transfer, not evidence of an operating Manila service.
      final ride =
          payload['data']['planConnection']['edges'][0]['node']['legs'][3];
      ride['mode'] = 'RAIL';
      ride['route']['shortName'] = 'Fixture connecting rail';
      final controller = JourneyController(
        provider: JourneyService(
          null,
          transit: OtpJourneyProvider(
            endpoint: Uri.parse('http://localhost:8090/plan'),
            client: MockClient(
              (request) async => http.Response(jsonEncode(payload), 200),
            ),
          ),
          road: (from, to, mode) async => RoutePlan([from, to], 14, 8085.2),
        ),
      );
      final planner = Planner(null, journey: controller)..local = true;
      final classStart = manilaNow().add(const Duration(hours: 2));
      planner.payload['classes'] = [
        {
          'id': 'fixture-class',
          'name': 'Synthetic class',
          'campus': 'FEU Tech',
          'day': classStart.weekday % 7,
          'time':
              '${classStart.hour.toString().padLeft(2, '0')}:${classStart.minute.toString().padLeft(2, '0')}',
          'room': 'Fixture',
        },
      ];
      configure(controller);
      await tester.pumpWidget(
        MaterialApp(
          theme: tamarawTheme('forest'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Commute(planner: planner, onSave: () async {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await controller.refresh();
      await tester.pumpAndSettle();
      final journey = controller.selected!;
      expect(find.text('Best available journey'), findsOneWidget);
      expect(find.text('Board at Fixture boarding station'), findsOneWidget);
      expect(find.text('Transfer to Fixture connecting rail'), findsOneWidget);
      expect(
        find.text('Leave by ${journeyClock(journey.departure!)}'),
        findsOneWidget,
      );
      expect(
        find.text('Estimated arrival ${journeyClock(journey.arrival!)}'),
        findsOneWidget,
      );
      expect(journey.duration, const Duration(minutes: 45));
      expect(journey.fare, isNull);
      expect(find.text('Driving estimate'), findsOneWidget);
      expect(find.text('Walking estimate'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );

  testWidgets(
    'Sakay-style steps show modes, stops, direction, transfers and final walk',
    (tester) async {
      final option = parseOtpJourneys(otpFixture(now), receivedAt: now).single;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [
        const Size(320, 740),
        const Size(768, 1024),
        const Size(1440, 1000),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: tamarawTheme('forest'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: JourneyTimeline(option: option),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Train'), findsOneWidget);
        expect(find.text('Bus / road transit'), findsOneWidget);
        expect(find.text('Board at Fixture boarding station'), findsOneWidget);
        expect(find.text('Toward Fixture southbound terminal'), findsOneWidget);
        expect(find.text('Alight at Fixture alighting stop'), findsOneWidget);
        expect(find.text('Transfer to Fixture Bus'), findsOneWidget);
        expect(
          find.text('Walk from Fixture alighting stop to FEU Tech'),
          findsOneWidget,
        );
        expect(
          find.text('Total estimate: 45 min 0 sec · 1 transfers'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
