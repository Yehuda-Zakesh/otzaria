import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import 'tools/calendar/support/calendar_alerts_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  test('שחזור ללא מקורות או מזהים אינו מאתחל את התוסף', () async {
    for (final empty in ['', '  ', 'null', '[]', '{}', 'broken']) {
      final notifications = WindowsLikeNotifications();
      final owner = CalendarAlertsOwner(
        store: MemoryAlertsStore({
          CalendarAlertsKeys.zmanAlerts: empty,
          CalendarAlertsKeys.events: empty,
        }),
        notifications: notifications,
        pluginEvents: () async => [],
        broadcast: (_) {},
      );
      await owner.restoreIfNeeded();
      expect(notifications.initCalls, 0, reason: empty);
      owner.dispose();
    }
  });

  for (final fromPlugin in [false, true]) {
    test('שחזור מקור עתידי ללא ledger: plugin=$fromPlugin', () async {
      var now = DateTime(2026, 10, 20, 9);
      final event = futureEvent(fromPlugin ? 'p:future' : 'future').copyWith(
        baseGregorianDate: DateTime(2027, 2, 1),
        recurrenceType: RecurrenceType.weekly,
      );
      final store = MemoryAlertsStore({
        if (!fromPlugin)
          CalendarAlertsKeys.events: jsonEncode([event.toJson()]),
      });
      CalendarAlertsOwner create(WindowsLikeNotifications notifications) =>
          CalendarAlertsOwner(
            store: store,
            notifications: notifications,
            pluginEvents: () async => fromPlugin ? [event] : [],
            now: () => now,
            broadcast: (_) {},
            dedupeDuplicates: false,
          );
      final firstNotifications = WindowsLikeNotifications();
      final first = create(firstNotifications);
      await first.restoreIfNeeded();
      expect(store.ledger, isEmpty);
      expect(firstNotifications.initCalls, 0);
      first.dispose();

      now = DateTime(2027, 1, 31, 9);
      final notifications = WindowsLikeNotifications();
      final restarted = create(notifications);
      await restarted.restoreIfNeeded();
      expect(notifications.scheduled, isNotEmpty);
      expect(notifications.everyIdAtMostOnce, isTrue);
      restarted.dispose();
    });
  }

  test('מזהים שנשארו ללא מקור מבוטלים בשחזור', () async {
    final store = MemoryAlertsStore()..ledger = [101, 102];
    final notifications = WindowsLikeNotifications()
      ..counts.addAll({101: 1, 102: 1});
    final owner = CalendarAlertsOwner(
      store: store,
      notifications: notifications,
      pluginEvents: () async => [],
      broadcast: (_) {},
      dedupeDuplicates: false,
    );
    await owner.restoreIfNeeded();
    expect(notifications.cancelled.toSet(), {101, 102});
    expect(notifications.present, isEmpty);
    expect(store.ledger, isEmpty);
    owner.dispose();
  });
}
