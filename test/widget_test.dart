import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tamaraw_time/main.dart';
import 'package:tamaraw_time/src/planner.dart';
import 'package:tamaraw_time/src/routing.dart';

void main() {
  test('Weekly occurrences roll over and preserve midnight/PM times', () {
    final now = DateTime.utc(2026, 11, 2, 10);
    expect(
      nextOccurrence({'day': 1, 'time': '09:00'}, now),
      DateTime.utc(2026, 11, 9, 9),
    );
    expect(
      nextOccurrence({'day': 1, 'time': '21:00'}, now),
      DateTime.utc(2026, 11, 2, 21),
    );
    expect(
      nextOccurrence({'day': 2, 'time': '00:00'}, now),
      DateTime.utc(2026, 11, 3),
    );
    expect(clock(DateTime.utc(2026, 11, 2, 0, 5)), '12:05 AM');
    expect(
      nextOccurrence({
        'day': 1,
        'time': '09:00',
        'end': '10:30',
      }, DateTime.utc(2026, 11, 2, 9, 30)),
      DateTime.utc(2026, 11, 2, 9),
    );
  });
  test(
    'Schedule helpers detect conflicts and sort classes chronologically',
    () {
      final morning = {
        'day': 1,
        'time': '09:00',
        'end': '10:30',
        'name': 'Algorithms',
      };
      final touching = {
        'day': 1,
        'time': '10:30',
        'end': '12:00',
        'name': 'Physics',
      };
      final overlapping = {
        'day': 1,
        'time': '10:00',
        'end': '11:00',
        'name': 'English',
      };
      expect(classesOverlap(morning, touching), false);
      expect(classesOverlap(morning, overlapping), true);
      expect(classesOverlap(morning, {...overlapping, 'day': 2}), false);
      expect(
        classesOverlap(
          {
            ...morning,
            'weekdays': [1, 3],
          },
          {
            ...overlapping,
            'day': 2,
            'weekdays': [2, 3],
          },
        ),
        true,
      );

      final sorted = classesByDay([
        {'day': 1, 'time': '13:00', 'end': '14:00', 'name': 'Later'},
        {...morning},
        {'day': 1, 'time': '09:00', 'end': '10:00', 'name': 'Earlier'},
        {'day': 2, 'time': '08:00', 'end': '09:00', 'name': 'Tomorrow'},
      ], 1);
      expect(sorted.map((c) => c['name']).toList(), [
        'Algorithms',
        'Earlier',
        'Later',
      ]);

      expect(
        classStatus({
          ...morning,
          'day': DateTime.utc(2026, 11, 2).weekday % 7,
        }, DateTime.utc(2026, 11, 2, 8)),
        'Upcoming',
      );
      expect(
        classStatus({
          ...morning,
          'day': DateTime.utc(2026, 11, 2).weekday % 7,
        }, DateTime.utc(2026, 11, 2, 9, 30)),
        'In progress',
      );
      expect(
        classStatus({
          ...morning,
          'day': DateTime.utc(2026, 11, 2).weekday % 7,
        }, DateTime.utc(2026, 11, 2, 11)),
        'Completed',
      );
    },
  );
  test(
    'Class travel estimate prefers class then campus then global defaults',
    () {
      final planner = Planner(null);
      expect(planner.classTravelMinutes({'campus': 'FEU Tech'}), 55);
      expect(planner.classTravelMinutes({'campus': 'FEU Alabang'}), 110);
      expect(
        planner.classTravelMinutes({'campus': 'FEU Tech', 'travel': 42}),
        42,
      );
    },
  );
  test('Device planner persists data using the web payload schema', () async {
    SharedPreferences.setMockInitialValues({});
    final planner = Planner(null);
    await planner.load(deviceOnly: true);
    planner.payload['classes'] = [
      {
        'id': 'a',
        'name': 'Algorithms',
        'day': 1,
        'time': '09:00',
        'end': '10:30',
        'campus': 'FEU Tech',
        'room': '401',
      },
    ];
    planner.settings['theme'] = 'ocean';
    await planner.save('class_added');
    final restored = Planner(null);
    await restored.load(deviceOnly: true);
    expect(restored.classes.single['name'], 'Algorithms');
    expect(restored.settings['theme'], 'ocean');
  });
  test('Driving route uses the supported routing profile', () {
    expect(Routing.roadProfile('Driving'), 'car');
    expect(Routing.roadProfile('Walking'), 'foot');
  });
  test('Journey estimate adds mode-specific travel time', () {
    expect(journeyEstimateMinutes(60, 'Driving'), 87);
    expect(journeyEstimateMinutes(60, 'Walking'), 79);
    expect(journeyEstimateMinutes(60, 'Transit'), 90);
    expect(journeyEstimateMinutes(60, 'Jeepney'), 98);
  });
  test('Jeepney discovery excludes buses and UV services', () {
    expect(Routing.isJeepney({'route': 'bus', 'name': 'EDSA Carousel'}), false);
    expect(
      Routing.isJeepney({'route': 'bus', 'name': 'UV Express jeep'}),
      false,
    );
    expect(Routing.isJeepney({'route': 'bus', 'ref': 'T123'}), true);
    expect(
      Routing.isJeepney({'route': 'bus', 'ref': '23', 'name': 'Route 23'}),
      true,
    );
    expect(Routing.isJeepney({'route': 'bus', 'name': 'Route 23'}), true);
    expect(Routing.isJeepney({'route': 'jeepney'}), true);
  });
  testWidgets('Visual tutorial guides a local planner in live app sections', (
    tester,
  ) async {
    final payload = Planner.fresh();
    SharedPreferences.setMockInitialValues({
      'tamaraw_local': jsonEncode(payload),
    });
    await tester.pumpWidget(const TamarawTimeApp());
    await tester.tap(find.text('Continue on this device'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual-tutorial')), findsOneWidget);
    expect(find.text('1. Explore your dashboard'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('2. Try adding a class'), findsOneWidget);
    await tester.tap(find.byTooltip('Close tutorial'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visual-tutorial')), findsNothing);
    expect(find.text('Saved on this device'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Commute tutorial stage advances to settings', (tester) async {
    final payload = Planner.fresh();
    SharedPreferences.setMockInitialValues({
      'tamaraw_local': jsonEncode(payload),
    });
    await tester.pumpWidget(const TamarawTimeApp());
    await tester.tap(find.text('Continue on this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Class Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Data Structures');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('3. Check your commute'), findsOneWidget);
    await tester.tap(find.text('Continue to Settings'));
    await tester.pumpAndSettle();
    expect(find.text('4. Personalize your planner'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Replay tutorial guide returns to dashboard step one', (
    tester,
  ) async {
    final payload = Planner.fresh();
    payload['onboarding'] = {'finished': true};
    SharedPreferences.setMockInitialValues({
      'tamaraw_local': jsonEncode(payload),
    });
    await tester.pumpWidget(const TamarawTimeApp());
    await tester.tap(find.text('Continue on this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Replay tutorial guide'));
    await tester.tap(find.text('Replay tutorial guide'));
    await tester.pumpAndSettle();
    expect(find.text('1. Explore your dashboard'), findsOneWidget);
    expect(find.text('Good day, Tamaraw!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Local planner opens schedule and saves a class', (tester) async {
    final payload = Planner.fresh();
    payload['onboarding'] = {'finished': true};
    SharedPreferences.setMockInitialValues({
      'tamaraw_local': jsonEncode(payload),
    });
    await tester.pumpWidget(const TamarawTimeApp());
    await tester.tap(find.text('Continue on this device'));
    await tester.pumpAndSettle();
    expect(find.text('Good day, Tamaraw!'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Data Structures');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Data Structures'), findsNWidgets(2));
    final stored = jsonDecode(
      (await SharedPreferences.getInstance()).getString('tamaraw_local')!,
    );
    expect(stored['classes'][0]['name'], 'Data Structures');
    expect(stored['classes'][0]['time'], '09:00');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
