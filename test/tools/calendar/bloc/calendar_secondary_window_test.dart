import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/calendar_alerts_fakes.dart';

/// בלי בעלים רשום באפיק: כל כתיבה של הגדרות נרשמת, כדי לוודא שאין כזו.
class _Settings implements SettingsRepository {
  final writes = <Symbol>[];

  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': jsonEncode([futureEvent('e1').toJson()]),
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
  dynamic noSuchMethod(Invocation invocation) {
    writes.add(invocation.memberName);
    return Future<void>.value();
  }
}

class _Plugins implements CalendarPluginSource {
  @override
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> events, {
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) async => events;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  late _Settings settings;
  late List<Map<String, Object?>> applied;
  late CalendarCubit cubit;

  setUp(() async {
    WindowBus.namespace = 'otzaria.test.calendar.noowner';
    settings = _Settings();
    applied = [];
    cubit = CalendarCubit(
      settingsRepository: settings,
      alertsClient: RemoteCalendarAlertsClient(
        applyValues: (values) async {
          applied.add(values);
          return true;
        },
      ),
      pluginCalendarAdapter: _Plugins(),
    );
    await cubit.initialized;
  });

  tearDown(() async {
    await cubit.close();
    WindowBus.namespace = 'otzaria.window';
  });

  test('(ה) בלי בעלים: אין כתיבה, וה-cubit חוזר למצב הקודם', () async {
    await cubit.addEvent(
      title: 'חדש',
      baseGregorianDate: DateTime(2026, 10, 26),
      recurrenceType: RecurrenceType.none,
    );
    expect(cubit.state.events.map((e) => e.id), ['e1']);

    await cubit.deleteEvent('e1');
    expect(cubit.state.events.map((e) => e.id), ['e1']);

    await cubit.changeCalendarNotificationTime(15);
    expect(cubit.state.calendarNotificationTime, 60);

    expect(settings.writes, isEmpty);
    expect(applied, isEmpty);
  });
}
