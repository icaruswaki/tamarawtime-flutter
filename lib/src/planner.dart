import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../transit/transit_repository.dart';
import 'journey_controller.dart';
import 'journey_service.dart';

const campuses = ['FEU Tech', 'FEU Manila', 'FEU Diliman', 'FEU Alabang'];
const days = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const modes = ['Transit', 'Jeepney', 'Train', 'Bus / UV', 'Driving', 'Walking'];
const classDeliveryModes = ['Face-to-Face', 'Online'];
DateTime manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
String clock(DateTime date) =>
    '${date.hour % 12 == 0 ? 12 : date.hour % 12}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
String classTime(String value) {
  final parts = value.split(':').map(int.parse).toList();
  return clock(DateTime.utc(2000, 1, 1, parts[0], parts[1]));
}

List<int> classWeekdays(Map<String, dynamic> entry) =>
    entry['weekdays'] is List && (entry['weekdays'] as List).isNotEmpty
    ? (entry['weekdays'] as List).cast<int>()
    : [entry['day'] as int];

int timeToMinutes(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return 0;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return 0;
  }
  return hour * 60 + minute;
}

bool classesOverlap(Map<String, dynamic> first, Map<String, dynamic> second) {
  final sharedDays = classWeekdays(first)
      .toSet()
      .intersection(classWeekdays(second).toSet());
  if (sharedDays.isEmpty) return false;
  final firstStart = timeToMinutes('${first['time']}');
  final firstEnd = timeToMinutes('${first['end']}');
  final secondStart = timeToMinutes('${second['time']}');
  final secondEnd = timeToMinutes('${second['end']}');
  return firstStart < secondEnd && secondStart < firstEnd;
}

String classStatus(Map<String, dynamic> c, DateTime now) {
  if (!classWeekdays(c).contains(now.weekday % 7)) return 'Upcoming';
  final currentMinute = now.hour * 60 + now.minute;
  final start = timeToMinutes('${c['time']}');
  final end = timeToMinutes('${c['end']}');
  if (currentMinute < start) return 'Upcoming';
  if (currentMinute < end) return 'In progress';
  return 'Completed';
}

List<Map<String, dynamic>> classesByDay(
  List<Map<String, dynamic>> classes,
  int day,
) {
  final result = classes.where((c) => classWeekdays(c).contains(day)).toList();
  result.sort((a, b) {
    final timeComparison = timeToMinutes('${a['time']}')
        .compareTo(timeToMinutes('${b['time']}'));
    return timeComparison != 0
        ? timeComparison
        : '${a['name']}'.compareTo('${b['name']}');
  });
  return result;
}

List<Map<String, dynamic>> classesOnDate(
  List<Map<String, dynamic>> classes,
  DateTime date,
) =>
    classes.where((c) => classWeekdays(c).contains(date.weekday % 7)).toList()
      ..sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

String occurrenceKey(Map<String, dynamic> c, DateTime date) =>
    '${c['id']}|${dateKey(date)}';

bool isOnlineClass(Map<String, dynamic> c) =>
    (c['classMode'] ?? c['delivery'] ?? 'Face-to-Face') == 'Online';

String attendanceStatus(
  Map<String, dynamic> c,
  DateTime occurrenceDate,
  DateTime now, {
  int bufferMinutes = 15,
}) {
  final startParts = '${c['time']}'.split(':').map(int.parse).toList();
  final start = DateTime.utc(
    occurrenceDate.year,
    occurrenceDate.month,
    occurrenceDate.day,
    startParts[0],
    startParts[1],
  );
  final checkIn = now.toUtc();
  if (checkIn.isBefore(start.subtract(Duration(minutes: bufferMinutes)))) {
    return 'Early';
  }
  if (!checkIn.isAfter(start)) return 'On Time';
  return 'Late';
}

int journeyEstimateMinutes(int baseMinutes, String mode) {
  final addition = switch (mode) {
    'Walking' => 10,
    'Driving' => 15,
    'Train' => 10,
    'Bus / UV' => 20,
    'Jeepney' => 20,
    _ => 15,
  };
  final multiplier = switch (mode) {
    'Walking' => 1.15,
    'Driving' => 1.20,
    'Train' => 1.10,
    'Bus / UV' => 1.25,
    'Jeepney' => 1.30,
    _ => 1.25,
  };
  return (baseMinutes * multiplier + addition).round().clamp(1, 480);
}

DateTime nextOccurrence(
  Map<String, dynamic> c,
  DateTime now, {
  bool includeInProgress = true,
}) {
  if (classWeekdays(c).length > 1) {
    final occurrences =
        classWeekdays(c)
            .map(
              (day) => nextOccurrence(
                {
                  ...c,
                  'day': day,
                  'weekdays': [day],
                },
                now,
                includeInProgress: false,
              ),
            )
            .toList()
          ..sort();
    return occurrences.first;
  }
  final weekday = classWeekdays(c).first;
  final t = (c['time'] as String).split(':').map(int.parse).toList();
  var date = DateTime.utc(
    now.year,
    now.month,
    now.day + (weekday - now.weekday % 7 + 7) % 7,
    t[0],
    t[1],
  );
  final nowUtc = DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
    now.second,
  );
  final endTime = c['end']?.toString();
  if (includeInProgress &&
      weekday == now.weekday % 7 &&
      endTime != null &&
      now.hour * 60 + now.minute >= timeToMinutes('${c['time']}') &&
      now.hour * 60 + now.minute < timeToMinutes(endTime)) {
    return date;
  }
  if (!date.isAfter(nowUtc)) {
    date = date.add(const Duration(days: 7));
  }
  return date;
}

class Planner extends ChangeNotifier {
  Planner(this.cloud, {JourneyController? journey, TransitRepository? transit})
    : transit = transit ?? TransitRepository(),
      journey = journey ?? JourneyController(provider: JourneyService(cloud)) {
    this.journey.addListener(notifyListeners);
  }
  final SupabaseClient? cloud;
  final JourneyController journey;
  final TransitRepository transit;
  // Explicit session choice, reset at logout. No eligibility inference or new
  // personal/student records are written to Supabase.
  bool studentDiscount = false;
  void selectStudentDiscount(bool value) {
    studentDiscount = value;
    notifyListeners();
  }

  Future<void> selectTravelMode(String mode) {
    if (!const {'Transit', 'Walking', 'Driving'}.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'Unsupported commute mode');
    }
    settings['mode'] = mode;
    settings['travelMode'] = mode;
    notifyListeners();
    return save();
  }

  bool local = false;
  String? _loadedUserId;
  Map<String, dynamic> payload = fresh();
  static Map<String, dynamic> fresh() => {
    'classes': <dynamic>[],
    'tasks': <dynamic>[],
    'attendance': <dynamic>[],
    'daysOff': <dynamic>[],
    'noClassOverrides': <dynamic>[],
    'settings': {
      'name': 'Tamaraw',
      'campus': 'FEU Tech',
      'travel': 55,
      'prep': 45,
      'buffer': 15,
      'punctualityNotificationsEnabled': false,
      'mode': 'Transit',
      'trafficBufferMinutes': 30,
      'campusTravel': {
        'FEU Tech': 55,
        'FEU Manila': 75,
        'FEU Diliman': 90,
        'FEU Alabang': 110,
      },
      'theme': 'forest',
    },
    'onboarding': {'finished': false},
  };
  Map<String, dynamic> get settings =>
      payload['settings'] as Map<String, dynamic>;
  void clearMemory() {
    studentDiscount = false;
    journey.clear();
    payload = fresh();
    local = false;
    _loadedUserId = null;
    notifyListeners();
  }

  List<Map<String, dynamic>> get classes => (payload['classes'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> get attendanceRecords =>
      ((payload['attendance'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  List<Map<String, dynamic>> get daysOff =>
      ((payload['daysOff'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  List<Map<String, dynamic>> get noClassOverrides =>
      ((payload['noClassOverrides'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  bool isDayOff(DateTime date) {
    final day = dateOnly(date);
    return daysOff.any((entry) {
      final start = DateTime.tryParse('${entry['start']}');
      final end = DateTime.tryParse('${entry['end'] ?? entry['start']}');
      if (start == null || end == null) return false;
      final first = dateOnly(start), last = dateOnly(end);
      return !day.isBefore(first) && !day.isAfter(last);
    });
  }

  bool isNoClassFor(Map<String, dynamic> c, DateTime date) =>
      noClassOverrides.any(
        (entry) =>
            entry['classId'] == c['id'] && entry['date'] == dateKey(date),
      );

  bool isOccurrenceExcluded(Map<String, dynamic> c, DateTime date) =>
      isDayOff(date) || isNoClassFor(c, date);

  DateTime nextPlannedOccurrence(Map<String, dynamic> c, DateTime now) {
    var result = nextOccurrence(c, now);
    for (var i = 0; i < 370 && isOccurrenceExcluded(c, result); i++) {
      result = nextOccurrence(
        c,
        result.add(const Duration(days: 1)),
        includeInProgress: false,
      );
    }
    return result;
  }

  List<Map<String, dynamic>> classesForDate(DateTime date) =>
      classesOnDate(classes, date);

  Map<String, dynamic>? attendanceFor(Map<String, dynamic> c, DateTime date) {
    final key = occurrenceKey(c, date);
    for (final record in attendanceRecords.reversed) {
      if (record['key'] == key) return record;
    }
    return null;
  }

  /// Records one personal check-in per class occurrence. This is not official
  /// university attendance and is stored with the rest of the local planner.
  String attendClass(Map<String, dynamic> c, DateTime date, {DateTime? now}) {
    final existing = attendanceFor(c, date);
    if (existing != null) return '${existing['status']}';
    final checkedAt = now ?? manilaNow();
    final record = {
      'key': occurrenceKey(c, date),
      'classId': c['id'],
      'className': c['name'],
      'date': dateKey(date),
      'status': attendanceStatus(
        c,
        date,
        checkedAt,
        bufferMinutes: (settings['buffer'] as num?)?.toInt() ?? 15,
      ),
      'recordedAt': checkedAt.toIso8601String(),
    };
    payload['attendance'] = [...attendanceRecords, record];
    notifyListeners();
    return '${record['status']}';
  }

  void setNoClassForToday(Map<String, dynamic> c, DateTime date) {
    if (isNoClassFor(c, date)) return;
    payload['noClassOverrides'] = [
      ...noClassOverrides,
      {'classId': c['id'], 'date': dateKey(date), 'className': c['name']},
    ];
    notifyListeners();
  }

  void undoNoClassForToday(Map<String, dynamic> c, DateTime date) {
    payload['noClassOverrides'] = noClassOverrides
        .where(
          (entry) =>
              !(entry['classId'] == c['id'] && entry['date'] == dateKey(date)),
        )
        .toList();
    notifyListeners();
  }

  void addDaysOff(DateTime start, DateTime end, {String label = 'Day off'}) {
    final first = dateOnly(start), last = dateOnly(end);
    payload['daysOff'] = [
      ...daysOff,
      {
        'start': dateKey(first),
        'end': dateKey(last.isBefore(first) ? first : last),
        'label': label.trim().isEmpty ? 'Day off' : label.trim(),
      },
    ];
    notifyListeners();
  }

  void removeDaysOff(Map<String, dynamic> entry) {
    payload['daysOff'] = daysOff
        .where(
          (item) =>
              item['start'] != entry['start'] || item['end'] != entry['end'],
        )
        .toList();
    notifyListeners();
  }

  int classTravelMinutes(Map<String, dynamic> c) {
    final direct = (c['travel'] as num?)?.toInt();
    if (direct != null && direct > 0) return direct;
    final campus = '${c['campus']}';
    final campusTravel = settings['campusTravel'] as Map?;
    final campusEstimate = (campusTravel?[campus] as num?)?.toInt();
    if (campusEstimate != null && campusEstimate > 0) return campusEstimate;
    return (settings['travel'] as num).toInt();
  }

  List<Map<String, dynamic>> get upcoming =>
      classes
          .where(
            (c) =>
                !isOccurrenceExcluded(c, nextPlannedOccurrence(c, manilaNow())),
          )
          .toList()
        ..sort(
          (a, b) => nextPlannedOccurrence(
            a,
            manilaNow(),
          ).compareTo(nextPlannedOccurrence(b, manilaNow())),
        );
  Future<void> load({bool deviceOnly = false}) async {
    final requestedUserId = deviceOnly ? null : cloud?.auth.currentUser?.id;
    if (!deviceOnly && requestedUserId == null) {
      throw StateError('Your session expired. Sign in again.');
    }
    local = deviceOnly;
    dynamic data;
    if (local) {
      final raw = (await SharedPreferences.getInstance()).getString(
        'tamaraw_local',
      );
      if (raw != null) data = jsonDecode(raw);
    } else {
      final row = await cloud!
          .from('app_states')
          .select('payload')
          .eq('user_id', requestedUserId!)
          .maybeSingle();
      data = row?['payload'];
      if (cloud?.auth.currentUser?.id != requestedUserId) {
        throw StateError(
          'The account changed while loading. Please sign in again.',
        );
      }
    }
    _loadedUserId = requestedUserId;
    payload = fresh();
    if (data is Map) {
      payload.addAll(Map<String, dynamic>.from(data));
      payload['settings'] = <String, dynamic>{
        ...fresh()['settings'] as Map,
        ...data['settings'] as Map? ?? {},
      };
    }
    notifyListeners();
  }

  Future<void> _queue = Future.value();
  Future<void> waitForSaves() => _queue;
  Future<void> save([String? event]) {
    final snapshot = jsonEncode(payload);
    final deviceOnly = local;
    final userId = cloud?.auth.currentUser?.id;
    final job = _queue.catchError((Object _) {}).then((_) async {
      if (deviceOnly) {
        await (await SharedPreferences.getInstance()).setString(
          'tamaraw_local',
          snapshot,
        );
      } else {
        if (userId == null ||
            userId != _loadedUserId ||
            cloud?.auth.currentUser?.id != userId) {
          throw StateError(
            'Your session changed. Sign in again before saving.',
          );
        }
        await cloud!.from('app_states').upsert({
          'user_id': userId,
          'payload': jsonDecode(snapshot),
        });
        if (event != null) {
          await cloud!.from('activity_events').insert({
            'user_id': userId,
            'event_type': event,
          });
        }
      }
    });
    _queue = job;
    notifyListeners();
    return job;
  }

  Future<void> log(String event) async {
    if (!local) {
      await cloud!.from('activity_events').insert({
        'user_id': cloud!.auth.currentUser!.id,
        'event_type': event,
      });
    }
  }

  @override
  void dispose() {
    journey.removeListener(notifyListeners);
    journey.dispose();
    super.dispose();
  }
}
