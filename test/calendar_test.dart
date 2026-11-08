import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:tamaraw_time/main.dart';
import 'package:tamaraw_time/src/planner.dart';

Map<String, dynamic> sampleClass(String id, int day, String start) => {
  'id': id,
  'name': id,
  'day': day,
  'time': start,
  'end': '23:30',
  'campus': 'FEU Tech',
  'room': '401',
};

void main() {
  test('Calendar reads legacy weekly schedules without rewriting data', () {
    final classes = [
      sampleClass('Morning', 1, '09:00'),
      sampleClass('Midnight', 1, '00:00'),
      sampleClass('Evening', 1, '21:00'),
      sampleClass('Tuesday', 2, '10:00'),
    ];
    final before = jsonEncode(classes);
    expect(
      classesOnDate(classes, DateTime.utc(2026, 11, 2)).map((c) => c['name']),
      ['Midnight', 'Morning', 'Evening'],
    );
    expect(classesOnDate(classes, DateTime.utc(2026, 11, 9)), hasLength(3));
    expect(classesOnDate(classes, DateTime.utc(2026, 11, 8)), isEmpty);
    expect(jsonEncode(classes), before);
    expect(classTime('00:00'), '12:00 AM');
    expect(classTime('12:05'), '12:05 PM');
    expect(classTime('21:00'), '9:00 PM');
  });

  test('Multiple weekdays feed both calendar and departure calculations', () {
    final entry = sampleClass('Lab', 1, '09:00')..['weekdays'] = [1, 3, 5];
    expect(classesOnDate([entry], DateTime.utc(2026, 11, 4)), hasLength(1));
    expect(classesOnDate([entry], DateTime.utc(2026, 11, 5)), isEmpty);
    expect(
      nextOccurrence(entry, DateTime.utc(2026, 11, 2, 10)),
      DateTime.utc(2026, 11, 4, 9),
    );
    expect(
      nextOccurrence(entry, DateTime.utc(2026, 11, 6, 10)),
      DateTime.utc(2026, 11, 9, 9),
    );
  });

  testWidgets(
    'Calendar selection, adding, editing and deleting preserve device storage',
    (tester) async {
      final now = manilaNow();
      final initial = Planner.fresh()..['onboarding'] = {'finished': true};
      initial['classes'] = [
        sampleClass('Existing class', now.weekday % 7, '09:00'),
      ];
      SharedPreferences.setMockInitialValues({
        'tamaraw_local': jsonEncode(initial),
      });
      final planner = Planner(null);
      addTearDown(planner.dispose);
      await tester.pumpWidget(TamarawTimeApp(planner: planner));
      await tester.tap(find.text('Continue on this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_month).first);
      await tester.pumpAndSettle();
      final tableFinder = find.byType(TableCalendar<Map<String, dynamic>>);
      final table = tester.widget<TableCalendar<Map<String, dynamic>>>(
        tableFinder,
      );
      expect(table.eventLoader!(now), hasLength(1));
      expect(find.text('Existing class'), findsOneWidget);
      final nextDay = now.add(const Duration(days: 1));
      table.onDaySelected!(nextDay, nextDay);
      await tester.pumpAndSettle();
      expect(find.text('Existing class'), findsNothing);
      await tester.ensureVisible(find.text('Add class for this day'));
      await tester.tap(find.text('Add class for this day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'New class');
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(
                FilterChip,
                days[nextDay.weekday % 7].substring(0, 3),
              ),
            )
            .selected,
        isTrue,
      );
      // Pick an additional recurring weekday without creating duplicate records.
      final other = (nextDay.weekday + 1) % 7;
      await tester.tap(
        find.widgetWithText(FilterChip, days[other].substring(0, 3)),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(planner.classes, hasLength(2));
      expect(classWeekdays(planner.classes.last), hasLength(2));
      await tester.ensureVisible(find.text('New class'));
      await tester.tap(find.text('New class'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Edited class');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(planner.classes, hasLength(2));
      expect(planner.classes.any((c) => c['name'] == 'Existing class'), isTrue);
      await tester.ensureVisible(find.byTooltip('Delete class'));
      await tester.tap(find.byTooltip('Delete class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(planner.classes, hasLength(2));
      await tester.tap(find.byTooltip('Delete class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      final restored = Planner(null);
      await restored.load(deviceOnly: true);
      expect(restored.classes.single['name'], 'Existing class');
      restored.dispose();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
