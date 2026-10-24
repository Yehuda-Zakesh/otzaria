import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../support/calendar_alerts_fakes.dart';

// Mock SettingsRepository
class MockSettingsRepository implements SettingsRepository {
  final Map<String, dynamic> _settings = {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': true,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': true,
    'calendarZmanAlerts': '{}',
    'calendarEnabledZmanim': '',
    'calendarDayTransition': 'sunset',
    'googleCalendarEnabled': false,
    'googleCalendarSelectedIds': 'primary',
    'googleCalendarSyncPastDays': 60,
    'googleCalendarSyncFutureDays': 365,
    'googleCalendarLastSync': 0,
  };

  @override
  Future<Map<String, dynamic>> loadSettings() async => _settings;

  @override
  Future<void> updateCalendarZmanAlertsJson(String json) async {
    _settings['calendarZmanAlerts'] = json;
  }

  @override
  Future<void> updateSelectedCity(String city) async {
    _settings['selectedCity'] = city;
  }

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  // Stubs for other methods to comply with interface
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalendarCubit Timezone Tests', () {
    late CalendarCubit calendarCubit;
    late WindowsLikeNotifications notifications;
    late CalendarAlertsOwner owner;

    setUp(() async {
      tz.initializeTimeZones();
      // Set a default global location to something else to prove we are not just using default
      tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));

      final settings = MockSettingsRepository();
      notifications = WindowsLikeNotifications();
      owner = CalendarAlertsOwner(
        store: RepositoryCalendarAlertsStore(settings),
        notifications: notifications,
        pluginEvents: () async => const [],
        dedupeDuplicates: false,
      );
      calendarCubit = CalendarCubit(
        settingsRepository: settings,
        alertsClient: LocalCalendarAlertsClient(owner),
      );
      await calendarCubit.initialized;
    });

    tearDown(() async {
      await owner.idle;
      await calendarCubit.close();
      owner.dispose();
    });

    Future<tz.TZDateTime> firstScheduledSunset() async {
      await calendarCubit.setZmanAlertPreference(
        timeId: 'sunset',
        displayName: 'שקיעה',
        minutesBefore: 15,
      );
      await owner.idle;
      expect(
        notifications.scheduled,
        isNotEmpty,
        reason: 'Notifications should be scheduled',
      );
      final eventDate = notifications.scheduled.first.eventDate;
      expect(eventDate, isA<tz.TZDateTime>());
      return eventDate as tz.TZDateTime;
    }

    test('Zman alert is scheduled with correct New York timezone', () async {
      await calendarCubit.changeCity('ניו יורק');

      final tzDate = await firstScheduledSunset();

      expect(tzDate.location.name, 'America/New_York');
    });

    test('Zman alert is scheduled with correct Jerusalem timezone', () async {
      final tzDate = await firstScheduledSunset();

      expect(tzDate.location.name, 'Asia/Jerusalem');
    });
  });
}
