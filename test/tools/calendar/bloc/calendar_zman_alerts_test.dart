import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../support/calendar_alerts_fakes.dart';

class _Settings implements SettingsRepository {
  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': false,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': false,
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
  Future<void> updateCalendarZmanAlertsJson(String json) async {}

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  final today = DateTime.now();
  late WindowsLikeNotifications notifications;
  late CalendarAlertsOwner owner;
  late CalendarCubit cubit;

  setUp(() async {
    notifications = WindowsLikeNotifications();
    final settings = _Settings();
    owner = CalendarAlertsOwner(
      store: RepositoryCalendarAlertsStore(settings),
      notifications: notifications,
      pluginEvents: () async => const [],
      // לפני הנץ, כדי שגם היום הראשון בחלון יתוזמן.
      now: () => DateTime(today.year, today.month, today.day, 0, 1),
      dedupeDuplicates: false,
    );
    cubit = CalendarCubit(
      settingsRepository: settings,
      alertsClient: LocalCalendarAlertsClient(owner),
    );
    await cubit.initialized;
  });

  tearDown(() async {
    await owner.idle;
    await cubit.close();
    owner.dispose();
  });

  test('a zman alert is scheduled for each day of the window', () async {
    await cubit.setZmanAlertPreference(
      timeId: 'sunrise',
      displayName: 'הנץ החמה',
      minutesBefore: 15,
    );
    await owner.idle;

    final scheduled = notifications.scheduled;
    expect(scheduled.length, 46);
    expect(scheduled.map((s) => s.id).toSet(), hasLength(46));
    expect(scheduled.every((s) => s.title == 'תזכורת: הנץ החמה'), isTrue);
    expect(scheduled.every((s) => s.minutes == 15), isTrue);
    expect(scheduled.first.body, startsWith('בעוד 15 דקות הנץ החמה ('));

    final first = scheduled.first.eventDate as tz.TZDateTime;
    expect(first.location.name, 'Asia/Jerusalem');
    expect(
      DateTime(first.year, first.month, first.day),
      DateTime(today.year, today.month, today.day),
    );
  });

  test('cancelling a zman alert cancels the whole window', () async {
    await cubit.setZmanAlertPreference(
      timeId: 'sunrise',
      displayName: 'הנץ החמה',
      minutesBefore: 15,
    );
    await owner.idle;
    final ids = notifications.present;

    await cubit.cancelZmanAlertPreference(timeId: 'sunrise');
    await owner.idle;

    expect(ids, hasLength(46));
    expect(notifications.present, isEmpty);
    expect(cubit.state.zmanAlerts, isEmpty);
  });
}
