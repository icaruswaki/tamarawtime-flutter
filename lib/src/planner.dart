import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
List<Map<String, dynamic>> classesOnDate(
  List<Map<String, dynamic>> classes,
  DateTime date,
) =>
    classes.where((c) => classWeekdays(c).contains(date.weekday % 7)).toList()
      ..sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
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
  if (classWeekdays(c).length > 1) {
    final occurrences =
        classWeekdays(c)
            .map(
              (day) => nextOccurrence({
                ...c,
                'day': day,
                'weekdays': [day],
              }, now),
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
  if (!date.isAfter(
    DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    ),
  )) {
    date = date.add(const Duration(days: 7));
  }
  return date;
}

class Planner extends ChangeNotifier {
  Planner(this.cloud, {JourneyController? journey})
    : journey = journey ?? JourneyController(provider: JourneyService(cloud)) {
    this.journey.addListener(notifyListeners);
  }
  final SupabaseClient? cloud;
  final JourneyController journey;
  bool local = false;
  String? _loadedUserId;
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
      'theme': 'forest',
    },
    'onboarding': {'finished': false},
  };
  Map<String, dynamic> get settings =>
      payload['settings'] as Map<String, dynamic>;
  void clearMemory() {
    journey.clear();
    payload = fresh();
    local = false;
    _loadedUserId = null;
    notifyListeners();
  }

  List<Map<String, dynamic>> get classes => (payload['classes'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> get upcoming => classes
    ..sort(
      (a, b) => nextOccurrence(
        a,
        manilaNow(),
      ).compareTo(nextOccurrence(b, manilaNow())),
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
