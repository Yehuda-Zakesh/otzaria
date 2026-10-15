import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_scheduler.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

class _Settings implements SettingsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RecordingNotifications implements NotificationService {
  final scheduledIds = <int>[];
  final scheduledMinutes = <int>[];
  final scheduledDates = <DateTime>[];
  final cancelled = <int>[];

  @override
  bool get isInitialized => true;

  @override
  Future<bool> checkPermissions() async => true;

  @override
  Future<void> cancelNotification(int id) async => cancelled.add(id);

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    scheduledIds.add(id);
    scheduledMinutes.add(reminderMinutes);
    scheduledDates.add(eventDate);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // The window from this date crosses the end of daylight saving time in
  // Israel (25.10.2026). The bug shows where the local time zone changes
  // its clock inside the window.
  final now = DateTime(2026, 10, 20, 9);
  const alerts = {
    'sunrise': ZmanAlertPreference(minutesBefore: 15, displayName: 'הנץ החמה'),
  };

  late _RecordingNotifications notifications;
  late CalendarAlertScheduler scheduler;

  setUp(() {
    notifications = _RecordingNotifications();
    scheduler = CalendarAlertScheduler(
      notifications: notifications,
      settings: _Settings(),
      now: () => now,
    );
  });

  test('the zman window schedules each calendar day once', () async {
    await scheduler.rescheduleZmanAlerts(alerts, 'ירושלים');

    final days = [
      for (final date in notifications.scheduledDates)
        DateTime(date.year, date.month, date.day),
    ];
    expect(days, [
      for (var i = 0; i <= 45; i++) DateTime(2026, 10, 20 + i),
    ]);
    expect(notifications.scheduledIds.toSet(), hasLength(46));
  });

  test('cancelling covers every day that was scheduled', () async {
    await scheduler.rescheduleZmanAlerts(alerts, 'ירושלים');
    final scheduled = notifications.scheduledIds.toSet();
    notifications.cancelled.clear();

    await scheduler.cancelZmanAlert('sunrise');

    expect(notifications.cancelled.toSet(), scheduled);
  });
  int notificationId(String timeId, DateTime date) =>
      '$timeId|${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}'
          .hashCode &
      0x7fffffff;

  test('שבת ויו״ט שומרים דקות שונות ומתוזמנים רק בצאת היום המתאים', () async {
    final scheduler = CalendarAlertScheduler(
      notifications: notifications,
      settings: _Settings(),
      now: () => DateTime(2026, 4, 1),
    );
    await scheduler.rescheduleZmanAlerts(const {
      'motzeiShabbos': ZmanAlertPreference(
        minutesBefore: 30,
        displayName: 'מוצאי שבת',
      ),
      'motzeiYomTov': ZmanAlertPreference(
        minutesBefore: 15,
        displayName: 'מוצאי יום טוב',
      ),
    }, 'ירושלים');
    expect(notifications.scheduledDates, isNotEmpty);
    expect(notifications.scheduledMinutes, containsAll([30, 15]));
    for (var i = 0; i < notifications.scheduledDates.length; i++) {
      final date = notifications.scheduledDates[i];
      final saturday = date.weekday == DateTime.saturday;
      final timeId = saturday ? 'motzeiShabbos' : 'motzeiYomTov';
      expect(notifications.scheduledIds[i], notificationId(timeId, date));
      expect(notifications.scheduledMinutes[i], saturday ? 30 : 15);
      if (!saturday) {
        expect(
          DateTime(date.year, date.month, date.day),
          isIn([DateTime(2026, 4, 2), DateTime(2026, 4, 8)]),
        );
      }
    }
    notifications.cancelled.clear();
    await scheduler.cancelZmanAlert('motzeiYomTov');
    expect(notifications.cancelled.toSet(), {
      for (var i = 0; i <= 45; i++)
        notificationId('motzeiYomTov', DateTime(2026, 4, 1 + i)),
    });
    expect(
      notifications.cancelled,
      isNot(contains(notificationId('motzeiShabbos', DateTime(2026, 4, 4)))),
    );
  });
}
