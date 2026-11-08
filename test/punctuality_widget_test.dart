import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamaraw_time/src/journey.dart';
import 'package:tamaraw_time/src/journey_controller.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/punctuality_overview.dart';
import 'package:tamaraw_time/src/theme.dart';
import 'package:tamaraw_time/src/commute.dart';

import 'support/journey_fixture.dart';

void main() {
  testWidgets(
    'Route options and itinerary steps reflow and selecting an option updates guidance',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now().toUtc();
      final provider = TestProvider()
        ..handler = (_) async => [
          JourneyOption(
            id: 'rail',
            duration: const Duration(minutes: 20),
            points: const [],
            updatedAt: now,
            steps: const [
              JourneyStep(mode: 'WALK', meters: 150),
              JourneyStep(
                mode: 'TRANSIT',
                lineName: 'Fixture rail',
                vehicle: 'SUBWAY',
                boardingStop: 'Fixture station',
                alightingStop: 'Fixture campus station',
              ),
            ],
          ),
          JourneyOption(
            id: 'bus',
            duration: const Duration(minutes: 30),
            points: const [],
            updatedAt: now,
            steps: const [
              JourneyStep(mode: 'WALK', meters: 200),
              JourneyStep(
                mode: 'TRANSIT',
                lineName: 'Fixture bus',
                vehicle: 'BUS',
                boardingStop: 'Fixture bus stop',
                alightingStop: 'Fixture campus stop',
              ),
            ],
          ),
        ];
      final controller = JourneyController(provider: provider);
      final planner = Planner(null, journey: controller)..local = true;
      configure(controller);
      await controller.refresh();
      Widget app(double scale) => MaterialApp(
        theme: tamarawTheme('forest'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Commute(planner: planner, onSave: () async {}),
          ),
        ),
      );
      await tester.pumpWidget(app(1));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('route-option-1')));
      await tester.tap(find.byKey(const ValueKey('route-option-1')));
      await tester.pumpAndSettle();
      expect(controller.selected!.id, 'bus');
      expect(find.textContaining('Fixture bus'), findsWidgets);
      expect(find.text('Board at Fixture bus stop'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpWidget(app(2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );

  testWidgets(
    'Updated logo uses the supplied asset without cropping in light and dark themes',
    (tester) async {
      for (final theme in ['forest', 'night']) {
        await tester.pumpWidget(
          MaterialApp(
            theme: tamarawTheme(theme),
            home: const Scaffold(body: Brand()),
          ),
        );
        final image = tester.widget<Image>(find.byType(Image));
        expect(
          (image.image as AssetImage).assetName,
          'assets/images/tamaraw-logo.png',
        );
        expect(image.fit, BoxFit.contain);
        expect(image.semanticLabel, 'Tamaraw Time logo');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Dashboard shows loading and unavailable states, then applies a returned ETA',
    (tester) async {
      final response = Completer<List<JourneyOption>>();
      final provider = TestProvider()..handler = (_) => response.future;
      final controller = JourneyController(provider: provider);
      final planner = Planner(null, journey: controller)..local = true;
      final classStart = manilaNow().add(const Duration(hours: 2));
      planner.payload['classes'] = [
        {
          'id': 'test',
          'name': 'Upcoming lab',
          'campus': 'FEU Tech',
          'room': '401',
          'day': classStart.weekday % 7,
          'time':
              '${classStart.hour.toString().padLeft(2, '0')}:${classStart.minute.toString().padLeft(2, '0')}',
          'end': '23:59',
        },
      ];
      configure(controller);
      final request = controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: tamarawTheme('forest'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: planner,
                builder: (context, _) =>
                    PunctualityOverview(planner: planner, onCommute: () {}),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('ETA unavailable'), findsOneWidget);
      expect(find.text('Potentially late'), findsNothing);
      response.complete([sampleJourney(DateTime.now().toUtc(), minutes: 20)]);
      await request;
      await tester.pumpAndSettle();
      expect(find.text('20 min'), findsOneWidget);
      expect(find.textContaining('Leave by '), findsOneWidget);
      expect(find.text('On track'), findsOneWidget);
      expect(planner.payload.containsKey('origin'), isFalse);
      expect(planner.payload.containsKey('coordinates'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );
}
