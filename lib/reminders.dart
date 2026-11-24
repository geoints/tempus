import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'records.dart';

class Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _init() async {
    if (!_ready) tzdata.initializeTimeZones();
    final timezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezone.identifier));
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    _ready = true;
  }

  Future<bool> request() async {
    if (!available) return false;
    await _init();
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> refresh(List<Record> rows) async {
    if (!available || (!_ready && !rows.any((row) => row.reminder != null))) {
      return;
    }
    try {
      await _init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (await android?.areNotificationsEnabled() != true) return;
      final now = tz.TZDateTime.now(tz.local);
      final today = dayOnly(now);
      final desired = <int, (Record, tz.TZDateTime, DateTimeComponents?)>{};
      for (final row in rows) {
        final minutes = row.reminder;
        if (minutes == null) continue;
        tz.TZDateTime at(DateTime date) => tz.TZDateTime(
          tz.local,
          date.year,
          date.month,
          date.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (row.kind == Kind.habit) {
          final start = row.date.isAfter(today) ? row.date : today;
          for (final weekday in row.weekdays) {
            var next = shiftDay(today, (weekday - today.weekday + 7) % 7);
            if (!at(next).isAfter(now)) next = shiftDay(next, 7);
            var day = shiftDay(start, (weekday - start.weekday + 7) % 7);
            while (!at(day).isAfter(now) || row.doneOn(day)) {
              day = shiftDay(day, 7);
            }
            // Android's weekly matcher starts at the next weekday. For a later
            // start, schedule its first occurrence at the actual date.
            desired[row.id * 7 + weekday - 1] = (
              row,
              at(day),
              day == next ? DateTimeComponents.dayOfWeekAndTime : null,
            );
          }
        } else if (!row.doneOn(row.date) && at(row.date).isAfter(now)) {
          desired[row.id * 7] = (row, at(row.date), null);
        }
      }

      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        final slot = desired[item.id];
        if (slot != null && item.payload == _payload(slot)) {
          desired.remove(item.id);
        } else {
          await _plugin.cancel(id: item.id);
        }
      }
      for (final item in desired.entries) {
        final (row, date, recurrence) = item.value;
        await _plugin.zonedSchedule(
          id: item.key,
          title: row.title,
          body: row.kind.label,
          scheduledDate: date,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'tempus_plans',
              'Планы TEMPUS',
              channelDescription: 'Напоминания о задачах, привычках и целях',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: recurrence,
          payload: _payload(item.value),
        );
      }
    } catch (error) {
      debugPrint('TEMPUS reminders: ${error.runtimeType}');
    }
  }

  String _payload((Record, tz.TZDateTime, DateTimeComponents?) slot) =>
      '${slot.$2.millisecondsSinceEpoch}|${slot.$3?.name}|${slot.$1.title}';
}
