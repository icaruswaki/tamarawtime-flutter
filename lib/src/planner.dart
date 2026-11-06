import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
DateTime manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
String clock(DateTime date) =>
    '${date.hour % 12 == 0 ? 12 : date.hour % 12}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
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
  if ((first['day'] as num?)?.toInt() != (second['day'] as num?)?.toInt()) {
    return false;
  }
  final firstStart = timeToMinutes('${first['time']}');
  final firstEnd = timeToMinutes('${first['end']}');
  final secondStart = timeToMinutes('${second['time']}');
  final secondEnd = timeToMinutes('${second['end']}');
  return firstStart < secondEnd && secondStart < firstEnd;
}

List<Map<String, dynamic>> classesByDay(
  List<Map<String, dynamic>> classes,
  int day,
) {
  final result = classes
      .where((c) => (c['day'] as num?)?.toInt() == day)
      .toList();
  result.sort((a, b) {
    final timeComparison = timeToMinutes('${a['time']}')
        .compareTo(timeToMinutes('${b['time']}'));
    if (timeComparison != 0) return timeComparison;
    return '${a['name']}'.compareTo('${b['name']}');
  });
  return result;
}

String classStatus(Map<String, dynamic> c, DateTime now) {
  final weekday = now.weekday % 7;
  final classDay = (c['day'] as num?)?.toInt();
  if (classDay != weekday) return 'Upcoming';
  final currentMinute = now.hour * 60 + now.minute;
  final start = timeToMinutes('${c['time']}');
  final end = timeToMinutes('${c['end']}');
  if (currentMinute < start) return 'Upcoming';
  if (currentMinute < end) return 'In progress';
  return 'Completed';
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

DateTime nextOccurrence(Map<String, dynamic> c, DateTime now) {
  final t = (c['time'] as String).split(':').map(int.parse).toList();
  var date = DateTime.utc(
    now.year,
    now.month,
    now.day + ((c['day'] as num).toInt() - now.weekday % 7 + 7) % 7,
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
  final classDay = (c['day'] as num).toInt();
  final endTime = c['end']?.toString();
  if (classDay == now.weekday % 7 && endTime != null) {
    final currentMinute = now.hour * 60 + now.minute;
    final startMinute = timeToMinutes('${c['time']}');
    final endMinute = timeToMinutes(endTime);
    if (currentMinute >= startMinute && currentMinute < endMinute) {
      return date;
    }
  }
  if (!date.isAfter(nowUtc)) {
    date = date.add(const Duration(days: 7));
  }
  return date;
}

class Planner extends ChangeNotifier {
  Planner(this.cloud);
  final SupabaseClient? cloud;
  bool local = false;
  Map<String, dynamic> payload = fresh();
  static Map<String, dynamic> fresh() => {
    'classes': <dynamic>[],
    'tasks': <dynamic>[],
    'settings': {
      'name': 'Tamaraw',
      'campus': 'FEU Tech',
      'travel': 55,
      'prep': 45,
      'buffer': 15,
      'mode': 'Transit',
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
  List<Map<String, dynamic>> get classes => (payload['classes'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  int classTravelMinutes(Map<String, dynamic> c) {
    final direct = (c['travel'] as num?)?.toInt();
    if (direct != null && direct > 0) return direct;
    final campus = '${c['campus']}';
    final campusTravel = settings['campusTravel'] as Map?;
    final campusEstimate = (campusTravel?[campus] as num?)?.toInt();
    if (campusEstimate != null && campusEstimate > 0) return campusEstimate;
    return (settings['travel'] as num).toInt();
  }

  List<Map<String, dynamic>> get upcoming => classes
    ..sort(
      (a, b) => nextOccurrence(
        a,
        manilaNow(),
      ).compareTo(nextOccurrence(b, manilaNow())),
    );
  Future<void> load({bool deviceOnly = false}) async {
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
          .eq('user_id', cloud!.auth.currentUser!.id)
          .maybeSingle();
      data = row?['payload'];
    }
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
    final job = _queue.catchError((Object _) {}).then((_) async {
      if (local) {
        await (await SharedPreferences.getInstance()).setString(
          'tamaraw_local',
          snapshot,
        );
      } else {
        await cloud!.from('app_states').upsert({
          'user_id': cloud!.auth.currentUser!.id,
          'payload': jsonDecode(snapshot),
        });
        if (event != null) await log(event);
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
}
