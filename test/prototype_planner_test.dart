import 'package:flutter_test/flutter_test.dart';
import 'package:tamaraw_time/src/planner.dart';

void main() {
  final monday = DateTime.utc(2026, 11, 9);
  final classEntry = <String, dynamic>{
    'id': 'math',
    'name': 'Math',
    'day': 1,
    'weekdays': [1],
    'time': '08:00',
    'end': '09:00',
    'campus': 'FEU Tech',
    'room': '',
  };

  test('attendance uses the configurable arrival buffer', () {
    expect(
      attendanceStatus(
        classEntry,
        monday,
        DateTime.utc(2026, 11, 9, 7, 44),
        bufferMinutes: 15,
      ),
      'Early',
    );
    expect(
      attendanceStatus(
        classEntry,
        monday,
        DateTime.utc(2026, 11, 9, 7, 45),
        bufferMinutes: 15,
      ),
      'On Time',
    );
    expect(
      attendanceStatus(
        classEntry,
        monday,
        DateTime.utc(2026, 11, 9, 8),
        bufferMinutes: 15,
      ),
      'On Time',
    );
    expect(
      attendanceStatus(
        classEntry,
        monday,
        DateTime.utc(2026, 11, 9, 8, 1),
        bufferMinutes: 15,
      ),
      'Late',
    );
  });

  test(
    'attendance records are idempotent and exceptions preserve recurrence',
    () {
      final planner = Planner(null);
      planner.payload['classes'] = [classEntry];
      planner.local = true;
      expect(
        planner.attendClass(
          classEntry,
          monday,
          now: DateTime.utc(2026, 11, 9, 7, 45),
        ),
        'On Time',
      );
      expect(
        planner.attendClass(
          classEntry,
          monday,
          now: DateTime.utc(2026, 11, 9, 8, 30),
        ),
        'On Time',
      );
      expect(planner.attendanceRecords, hasLength(1));

      planner.setNoClassForToday(classEntry, monday);
      expect(planner.isNoClassFor(classEntry, monday), isTrue);
      expect(planner.classes, hasLength(1));
      planner.undoNoClassForToday(classEntry, monday);
      expect(planner.isNoClassFor(classEntry, monday), isFalse);
      planner.dispose();
    },
  );

  test('date ranges mark classes as excluded without deleting them', () {
    final planner = Planner(null);
    planner.payload['classes'] = [classEntry];
    planner.addDaysOff(
      monday,
      monday.add(const Duration(days: 2)),
      label: 'Break',
    );
    expect(planner.isDayOff(monday), isTrue);
    expect(planner.isDayOff(monday.add(const Duration(days: 1))), isTrue);
    expect(planner.isDayOff(monday.add(const Duration(days: 3))), isFalse);
    expect(planner.classes, hasLength(1));
    planner.dispose();
  });
}
