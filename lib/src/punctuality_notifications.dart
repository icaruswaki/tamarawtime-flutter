import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'planner.dart';

enum PunctualityReminderKind { preparation, leaveBy, classStarts }

extension on PunctualityReminderKind {
  String get channelId => 'punctuality_v2_$name';
  String get soundName => switch (this) {
    PunctualityReminderKind.preparation => 'preparation',
    PunctualityReminderKind.leaveBy => 'leave_by',
    PunctualityReminderKind.classStarts => 'class_starts',
  };
  String get title => switch (this) {
    PunctualityReminderKind.preparation => 'Preparation time',
    PunctualityReminderKind.leaveBy => 'Leave for class',
    PunctualityReminderKind.classStarts => 'Class starts',
  };
  String get channelName => switch (this) {
    PunctualityReminderKind.preparation => 'Preparation reminders',
    PunctualityReminderKind.leaveBy => 'Leave-by reminders',
    PunctualityReminderKind.classStarts => 'Class start reminders',
  };
}

class PunctualityReminder {
  const PunctualityReminder({
    required this.classId,
    required this.className,
    required this.classStart,
    required this.leaveBy,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.kind,
  });

  final String classId;
  final String className;
  final String classStart;
  final String leaveBy;
  final int weekday;
  final int hour;
  final int minute;
  final PunctualityReminderKind kind;
}

List<PunctualityReminder> buildPunctualityReminders({
  required List<Map<String, dynamic>> classes,
  required Map<String, dynamic> settings,
}) {
  final preparation = (((settings['prep'] as num?)?.toInt() ?? 0).clamp(
    0,
    480,
  )).toInt();
  final buffer = (((settings['buffer'] as num?)?.toInt() ?? 0).clamp(
    0,
    480,
  )).toInt();
  final campusTravel = settings['campusTravel'] as Map?;
  final defaultTravel = (settings['travel'] as num?)?.toInt() ?? 55;
  final reminders = <PunctualityReminder>[];

  for (final entry in classes) {
    final startMinutes = _minutesOfDay(entry['time']);
    if (startMinutes == null) continue;
    final travel =
        (entry['travel'] as num?)?.toInt() ??
        (campusTravel?[entry['campus']] as num?)?.toInt() ??
        defaultTravel;
    if (travel < 0 || travel > 2880) continue;
    final classId =
        entry['id']?.toString() ?? '${entry['name']}:${entry['time']}';
    final className = entry['name']?.toString() ?? 'Class';
    final classStart = _formatTime(startMinutes);

    for (final weekday in classWeekdays(
      entry,
    ).where((day) => day >= 0 && day < 7)) {
      final start = DateTime.utc(
        2026,
        1,
        4 + weekday,
        0,
      ).add(Duration(minutes: startMinutes));
      final leave = start.subtract(Duration(minutes: travel + buffer));
      final prepare = leave.subtract(Duration(minutes: preparation));
      final leaveBy = _formatTime(leave.hour * 60 + leave.minute);
      reminders
        ..add(
          _reminder(
            classId,
            className,
            classStart,
            leaveBy,
            prepare,
            PunctualityReminderKind.preparation,
          ),
        )
        ..add(
          _reminder(
            classId,
            className,
            classStart,
            leaveBy,
            leave,
            PunctualityReminderKind.leaveBy,
          ),
        )
        ..add(
          _reminder(
            classId,
            className,
            classStart,
            leaveBy,
            start,
            PunctualityReminderKind.classStarts,
          ),
        );
    }
  }
  return reminders;
}

PunctualityReminder _reminder(
  String classId,
  String className,
  String classStart,
  String leaveBy,
  DateTime time,
  PunctualityReminderKind kind,
) => PunctualityReminder(
  classId: classId,
  className: className,
  classStart: classStart,
  leaveBy: leaveBy,
  weekday: time.weekday % 7,
  hour: time.hour,
  minute: time.minute,
  kind: kind,
);

int? _minutesOfDay(Object? value) {
  if (value is! String) return null;
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

String _formatTime(int minutes) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}';
}

class PunctualityNotifications {
  PunctualityNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _zoneName = 'Asia/Manila';
  static timezone.Location? _location;
  static Future<void>? _initializing;
  static bool _initialized = false;
  static String? _initializationError;
  static bool _exactAlarmPermissionRequested = false;
  static bool _exactAlarmAllowed = false;
  static int _scheduledReminderCount = 0;
  static String? _scheduleSyncError;
  static String? _nextReminderSummary;
  static String? _scheduleModeSummary;

  static String get lastSyncStatus =>
      _scheduleSyncError ??
      'Scheduled $_scheduledReminderCount punctuality notifications${_scheduleModeSummary == null ? '' : ' using $_scheduleModeSummary'}.${_nextReminderSummary == null ? '' : ' Next: $_nextReminderSummary.'}';

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() {
    if (!isSupported || _initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        AndroidFlutterLocalNotificationsPlugin.registerWith();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        IOSFlutterLocalNotificationsPlugin.registerWith();
      }
      timezone_data.initializeTimeZones();
      _location = timezone.getLocation(_zoneName);
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      if (initialized == false) {
        throw StateError(
          'The platform plugin returned an unsuccessful initialization result.',
        );
      }
      _initialized = true;
      _initializationError = null;
    } catch (error, stackTrace) {
      _initializing = null;
      _initializationError = '$error';
      debugPrint(
        'Could not initialize punctuality notifications: $error\n$stackTrace',
      );
    }
  }

  static Future<void> sync(Planner planner) async {
    if (!isSupported) return;
    _scheduledReminderCount = 0;
    _scheduleSyncError = null;
    _nextReminderSummary = null;
    _scheduleModeSummary = null;
    try {
      await initialize();
      if (!_initialized) {
        _scheduleSyncError =
            'The notification plugin did not initialize: ${_initializationError ?? 'unknown error'}';
        return;
      }
      await _plugin.cancelAll();
      if (planner.settings['punctualityNotificationsEnabled'] != true) {
        _scheduleSyncError = 'Punctuality notifications are turned off.';
        return;
      }
      final reminders = buildPunctualityReminders(
        classes: planner.classes,
        settings: planner.settings,
      );
      if (reminders.isEmpty) {
        _scheduleSyncError = 'No valid class times are available to schedule.';
        return;
      }
      if (!await requestPermission()) {
        _scheduleSyncError =
            'Android reports that notifications are disabled for Tamaraw Time.';
        return;
      }
      await _createAndroidChannels();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        _exactAlarmAllowed =
            await android?.canScheduleExactNotifications() == true;
      }
      final scheduleMode = _exactAlarmAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      _scheduleModeSummary = defaultTargetPlatform == TargetPlatform.android
          ? (_exactAlarmAllowed
                ? 'exact alarms'
                : 'inexact alarms; Android may delay them')
          : 'calendar alerts';

      final now = timezone.TZDateTime.now(_location!);
      final sorted = reminders.toList()
        ..sort((a, b) => _nextTime(a, now).compareTo(_nextTime(b, now)));
      final selected =
          (defaultTargetPlatform == TargetPlatform.iOS
                  ? sorted.take(64)
                  : sorted)
              .toList();
      await Future.wait(
        selected.map((reminder) => _schedule(reminder, now, scheduleMode)),
      );
      final ids = selected.map(_notificationId).toSet();
      final pending = await _plugin.pendingNotificationRequests();
      _scheduledReminderCount = pending
          .where((request) => ids.contains(request.id))
          .length;
      if (_scheduledReminderCount > 0 && selected.isNotEmpty) {
        final next = selected.first;
        final date = _nextTime(next, now);
        _nextReminderSummary =
            '${next.className} ${next.kind.title.toLowerCase()} on ${days[date.weekday % 7]} ${date.month}/${date.day} at ${_formatTime(date.hour * 60 + date.minute)}';
      }
    } catch (error, stackTrace) {
      _scheduleSyncError = 'Could not schedule class reminders: $error';
      debugPrint(
        'Could not sync punctuality notifications: $error\n$stackTrace',
      );
    }
  }

  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      await initialize();
      if (!_initialized || !await _requestPermission()) return false;
      if (defaultTargetPlatform == TargetPlatform.android &&
          !_exactAlarmPermissionRequested) {
        _exactAlarmPermissionRequested = true;
        _exactAlarmAllowed =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestExactAlarmsPermission() ==
            true;
      }
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Could not request notification permission: $error\n$stackTrace',
      );
      return false;
    }
  }

  static Future<String?> showTestNotification() async {
    if (!isSupported) return 'Notifications are unavailable on this platform.';
    try {
      await initialize();
      if (!_initialized) {
        return 'The notification plugin did not initialize: ${_initializationError ?? 'unknown error'}';
      }
      if (!await _requestPermission()) {
        return 'Android reports that notifications are disabled for Tamaraw Time.';
      }
      await _createAndroidChannels();
      await _plugin.show(
        id: 2147483646,
        title: 'Tamaraw Time test alert',
        body:
            'Punctuality notifications and the preparation sound are working.',
        notificationDetails: _preparationTestDetails,
      );
      return null;
    } catch (error, stackTrace) {
      debugPrint('Could not show test notification: $error\n$stackTrace');
      return 'Could not post the test notification: $error';
    }
  }

  static Future<String?> scheduleTestNotificationInTenSeconds() async {
    if (!isSupported) return 'Notifications are unavailable on this platform.';
    try {
      await initialize();
      if (!_initialized) {
        return 'The notification plugin did not initialize: ${_initializationError ?? 'unknown error'}';
      }
      if (!await _requestPermission()) {
        return 'Android reports that notifications are disabled for Tamaraw Time.';
      }
      await _createAndroidChannels();
      var exactAllowed = _exactAlarmAllowed;
      if (defaultTargetPlatform == TargetPlatform.android) {
        exactAllowed =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.canScheduleExactNotifications() ==
            true;
        _exactAlarmAllowed = exactAllowed;
      }
      final scheduledDate = timezone.TZDateTime.now(_location!)
          .add(const Duration(seconds: 10));
      await _plugin.zonedSchedule(
        id: 2147483645,
        title: 'Tamaraw Time test alert',
        body: 'This test notification was scheduled 10 seconds ago.',
        scheduledDate: scheduledDate,
        notificationDetails: _preparationTestDetails,
        androidScheduleMode: exactAllowed
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return null;
    } catch (error, stackTrace) {
      debugPrint(
        'Could not schedule 10-second test notification: $error\n$stackTrace',
      );
      return 'Could not schedule the test notification: $error';
    }
  }

  static NotificationDetails get _preparationTestDetails {
    const kind = PunctualityReminderKind.preparation;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        kind.channelId,
        kind.channelName,
        channelDescription: 'Timing alerts for your weekly class schedule.',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(kind.soundName),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: '${kind.soundName}.wav',
      ),
    );
  }

  static Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() == true) return true;
      final result = await android?.requestNotificationsPermission();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled != null) return enabled;
      return result != false;
    }
    final result = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    return result != false;
  }

  static Future<void> openSystemSettings() async {
    if (!isSupported) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.openAppNotificationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }

  static Future<void> _createAndroidChannels() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final kind in PunctualityReminderKind.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          kind.channelId,
          kind.channelName,
          description: 'Timing alerts for your weekly class schedule.',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(kind.soundName),
        ),
      );
    }
  }

  static Future<void> _schedule(
    PunctualityReminder reminder,
    timezone.TZDateTime now,
    AndroidScheduleMode scheduleMode,
  ) {
    final kind = reminder.kind;
    final startDay = (reminder.weekday - now.weekday % 7 + 7) % 7;
    var scheduled = timezone.TZDateTime(
      _location!,
      now.year,
      now.month,
      now.day + startDay,
      reminder.hour,
      reminder.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 7));
    }
    final body = switch (kind) {
      PunctualityReminderKind.preparation =>
        'Get ready for ${reminder.className}. Class starts at ${reminder.classStart}; leave by ${reminder.leaveBy}.',
      PunctualityReminderKind.leaveBy =>
        'Leave now for ${reminder.className}. Class starts at ${reminder.classStart}.',
      PunctualityReminderKind.classStarts =>
        '${reminder.className} starts now at ${reminder.classStart}.',
    };
    return _plugin.zonedSchedule(
      id: _notificationId(reminder),
      title: kind.title,
      body: body,
      scheduledDate: scheduled,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          kind.channelId,
          kind.channelName,
          channelDescription: 'Timing alerts for your weekly class schedule.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(kind.soundName),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          sound: '${kind.soundName}.wav',
        ),
      ),
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static timezone.TZDateTime _nextTime(
    PunctualityReminder reminder,
    timezone.TZDateTime now,
  ) {
    final dayOffset = (reminder.weekday - now.weekday % 7 + 7) % 7;
    var result = timezone.TZDateTime(
      _location!,
      now.year,
      now.month,
      now.day + dayOffset,
      reminder.hour,
      reminder.minute,
    );
    if (!result.isAfter(now)) result = result.add(const Duration(days: 7));
    return result;
  }

  static int _notificationId(PunctualityReminder reminder) {
    var hash = 0x811c9dc5;
    final key = '${reminder.classId}:${reminder.weekday}:${reminder.kind.name}';
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  static Future<void> cancelAll() async {
    if (!isSupported || !_initialized) return;
    await _plugin.cancelAll();
  }
}
