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
DateTime nextOccurrence(Map<String, dynamic> c, DateTime now) {
  final t = (c['time'] as String).split(':').map(int.parse).toList();
  var date = DateTime.utc(
    now.year,
    now.month,
    now.day + ((c['day'] as num).toInt() - now.weekday % 7 + 7) % 7,
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
      'theme': 'forest',
    },
    'onboarding': {'finished': false},
  };
  Map<String, dynamic> get settings =>
      payload['settings'] as Map<String, dynamic>;
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
