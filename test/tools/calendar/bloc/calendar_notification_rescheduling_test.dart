import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/calendar_alerts_fakes.dart';

final _now = DateTime(2026, 10, 2);

class _Settings implements SettingsRepository {
  String notificationIds = '[]';

  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': jsonEncode([
      CustomEvent(
        id: 'event',
        title: 'אירוע עתידי',
        description: '',
        createdAt: _now,
        baseGregorianDate: DateTime(2026, 10, 5),
        baseJewishYear: 5787,
        baseJewishMonth: 7,
        baseJewishDay: 24,
        recurrenceType: RecurrenceType.none,
        recurringYears: null,
      ).toJson(),
    ]),
    'calendarNotificationsEnabled': true,
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
  String getCalendarEventNotificationIdsJson() => notificationIds;

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String value) async =>
      notificationIds = value;

  @override
  Future<void> updateCalendarEvents(String value) async {}

  @override
  Future<void> updateCalendarNotificationTime(int value) async {}

  @override
  Future<void> updateCalendarNotificationsEnabled(bool value) async {}

  @override
  Future<void> updateCalendarNotificationSound(bool value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  late WindowsLikeNotifications notifications;
  late CalendarAlertsOwner owner;
  late CalendarCubit cubit;
  late Completer<void> cancellationStarted;

  setUp(() async {
    settings = _Settings();
    notifications = WindowsLikeNotifications();
    owner = CalendarAlertsOwner(
      store: RepositoryCalendarAlertsStore(settings),
      notifications: notifications,
      pluginEvents: () async => const [],
      now: () => _now,
      broadcast: (_) {},
      dedupeDuplicates: false,
    );
    cubit = CalendarCubit(
      settingsRepository: settings,
      alertsClient: LocalCalendarAlertsClient(owner),
      pluginCalendarAdapter: _Plugins(),
    );
    await cubit.initialized;
    await owner.restoreIfNeeded();
    notifications.scheduled.clear();
    cancellationStarted = Completer<void>();
    // הריצה הבאה נעצרת בביטול הראשון שלה.
    notifications.cancelGate = Completer<void>();
    notifications.onCancel = () {
      if (!cancellationStarted.isCompleted) cancellationStarted.complete();
    };
  });

  tearDown(() async {
    if (!notifications.cancelGate!.isCompleted) {
      notifications.cancelGate!.complete();
    }
    await owner.idle;
    await cubit.close();
    owner.dispose();
  });

  Future<void> release() async {
    notifications.cancelGate!.complete();
    await owner.idle;
  }

  test('disabling notifications during cancellation stays disabled', () async {
    await cubit.changeCalendarNotificationTime(15);
    await cancellationStarted.future;
    await cubit.changeCalendarNotificationsEnabled(false);
    await release();

    expect(cubit.state.calendarNotificationsEnabled, isFalse);
    expect(notifications.present, isEmpty);
    expect(settings.notificationIds, '[]');
  });

  test(
    'deleting an event during cancellation keeps its reminder deleted',
    () async {
      await cubit.changeCalendarNotificationTime(15);
      await cancellationStarted.future;
      await cubit.deleteEvent('event');
      await release();

      expect(cubit.state.events, isEmpty);
      expect(notifications.present, isEmpty);
      expect(settings.notificationIds, '[]');
    },
  );

  test('rescheduling after cancellation uses current time and sound', () async {
    await cubit.changeCalendarNotificationTime(15);
    await cancellationStarted.future;
    await cubit.changeCalendarNotificationTime(20);
    await cubit.changeCalendarNotificationSound(true);
    await release();

    expect(cubit.state.calendarNotificationTime, 20);
    expect(cubit.state.calendarNotificationSound, isTrue);
    expect(notifications.everyIdAtMostOnce, isTrue);
    expect(notifications.present, hasLength(1));
    final last = notifications.scheduled.last;
    expect((last.minutes, last.sound), (20, true));
  });
}
