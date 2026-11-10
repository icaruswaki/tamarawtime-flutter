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
    'Only the best transit route is shown alongside selectable road ETAs',
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
      expect(find.byKey(const ValueKey('route-option-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-option-1')), findsNothing);
      expect(controller.selected!.id, 'rail');
      expect(find.text('Walking estimate'), findsOneWidget);
      expect(find.text('Driving estimate'), findsOneWidget);
      await tester.ensureVisible(find.text('Driving estimate'));
      await tester.tap(find.text('Driving estimate'));
      await tester.pumpAndSettle();
      expect(controller.mode, 'Driving');
      expect(controller.selected!.minutes, 20);
      expect(find.byKey(const ValueKey('route-option-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-option-1')), findsNothing);
      await tester.ensureVisible(find.text('Walking estimate'));
      await tester.tap(find.text('Walking estimate'));
      await tester.pumpAndSettle();
      expect(controller.mode, 'Walking');
      expect(controller.selected!.minutes, 20);
      await tester.ensureVisible(find.byKey(const ValueKey('route-option-0')));
      await tester.tap(find.byKey(const ValueKey('route-option-0')));
      await tester.pumpAndSettle();
      expect(controller.mode, 'Transit');
      expect(controller.selected!.id, 'rail');
      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpWidget(app(2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      planner.dispose();
    },
  );

  testWidgets('Expired rail option remains visible after an empty refresh', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    var transitRequests = 0;
    final provider = TestProvider()
      ..handler = (query) async {
        if (query.mode == 'Transit') {
          transitRequests++;
          return transitRequests == 1
              ? [
                  JourneyOption(
                    id: 'rail',
                    duration: const Duration(minutes: 20),
                    points: const [],
                    updatedAt: now.subtract(const Duration(minutes: 6)),
                    steps: const [
                      JourneyStep(mode: 'TRANSIT', vehicle: 'RAIL'),
                    ],
                  ),
                ]
              : [];
        }
        return [sampleJourney(now, id: query.mode, minutes: 16)];
      };
    final controller = JourneyController(provider: provider, now: () => now);
    final planner = Planner(null, journey: controller)..local = true;
    configure(controller);
    await controller.refresh();
    planner.settings['mode'] = 'Driving';
    controller.configure(
      destination: controller.destination!,
      label: 'FEU Tech',
      mode: 'Driving',
      autoRefresh: false,
    );
    await controller.refresh();

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
    expect(controller.bestTransitOption, isNull);
    expect(controller.cachedTransitOption?.id, 'rail');
    expect(find.byKey(const ValueKey('route-option-0')), findsOneWidget);
    expect(find.text('Previous ETA · 20 min'), findsOneWidget);
    expect(find.text('Previous itinerary · select to refresh'), findsOneWidget);
    expect(transitRequests, 2);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    planner.dispose();
  });

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

  testWidgets('Home ETA label and value follow the selected travel mode', (
    tester,
  ) async {
    final provider = TestProvider()
      ..handler = (query) async => [
        sampleJourney(
          DateTime.now().toUtc(),
          id: query.mode,
          minutes: switch (query.mode) {
            'Walking' => 12,
            'Driving' => 18,
            _ => 25,
          },
        ),
      ];
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
    await controller.refresh();

    Widget home() => MaterialApp(
      theme: tamarawTheme('forest'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PunctualityOverview(planner: planner, onCommute: () {}),
        ),
      ),
    );

    planner.settings['mode'] = 'Walking';
    await tester.pumpWidget(home());
    expect(find.text('Walking ETA'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);

    planner.settings['mode'] = 'Driving';
    planner.settings['trafficBufferMinutes'] = 15;
    await tester.pumpWidget(home());
    expect(find.text('Driving ETA'), findsOneWidget);
    expect(find.text('33 min'), findsOneWidget);

    planner.settings['mode'] = 'Transit';
    await tester.pumpWidget(home());
    expect(find.text('Public transit ETA'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    planner.dispose();
  });
}
