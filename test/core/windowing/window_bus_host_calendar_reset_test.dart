import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_bus_host.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../../tools/calendar/support/calendar_alerts_fakes.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

/// איפוס מחלון משני מוחק בחלון הראשי גם את רישום ההתראות, ולכן הבעלים
/// חייב לבטל לפי מה שבזיכרון.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  late MemoryAlertsStore store;
  late WindowsLikeNotifications notifications;
  late CalendarAlertsOwner owner;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = 'otzaria.test.bushost.calendarreset';
    store = MemoryAlertsStore({
      CalendarAlertsKeys.events: jsonEncode([futureEvent('a').toJson()]),
    });
    notifications = WindowsLikeNotifications();
    owner = CalendarAlertsOwner(
      store: store,
      notifications: notifications,
      pluginIds: MemoryPluginIds(),
      pluginEvents: () async => const [],
      now: () => DateTime(2026, 10, 20, 9),
      broadcast: (_) {},
      dedupeDuplicates: false,
    );
    CalendarAlertsOwner.instanceForTesting = owner;
  });

  tearDown(() {
    owner.dispose();
    CalendarAlertsOwner.instanceForTesting = null;
    SettingsSync.instance.clearLocally = null;
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    WindowBus.namespace = 'otzaria.window';
    MultiWindowService.debugSupportedOverride = null;
    WindowRole.isSecondary = false;
  });

  Future<int> resetFromAnotherWindow(WidgetTester tester) async {
    await tester.runAsync(owner.restoreIfNeeded);
    expect(notifications.present, {reminderId('a')});
    // מה שהאיפוס מוחק ב-box: גם האירועים וגם הרישום השמור.
    SettingsSync.instance.clearLocally = () async {
      store.values
        ..clear()
        ..addAll(CalendarAlertsKeys.defaults);
      store.ledger = [];
    };
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: _MockSettingsBloc(),
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    final revision = owner.revision;
    await tester.runAsync(
      () => SettingsSync.instance.handleRequest({
        'type': SettingsSync.requestReset,
      }),
    );
    // המאזין נרשם בתוך ה-zone של הבדיקה; ההמשכים שלו מתקדמים ב-pump.
    for (var i = 0; i < 100 && notifications.present.isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    return revision;
  }

  testWidgets('בחלון הראשי הבעלים משדר ומבטל את ההתראות שנמחקו', (
    tester,
  ) async {
    final revision = await resetFromAnotherWindow(tester);

    expect(owner.revision, revision + 1);
    expect(notifications.present, isEmpty);
  });

  testWidgets('שינוי הגדרה רגיל מחלון אחר אינו מיישר את הבעלים', (
    tester,
  ) async {
    await tester.runAsync(owner.restoreIfNeeded);
    SettingsSync.instance.applyLocally = (_, _) async {};
    addTearDown(() => SettingsSync.instance.applyLocally = null);
    await tester.pumpWidget(
      BlocProvider<SettingsBloc>.value(
        value: _MockSettingsBloc(),
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    final revision = owner.revision;

    await tester.runAsync(
      () => SettingsSync.instance.handleRequest({
        'type': SettingsSync.requestChanged,
        'key': 'key-font-size',
        'value': 20,
      }),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(owner.revision, revision);
    expect(notifications.present, {reminderId('a')});
  });

  testWidgets('בחלון משני הבעלים אינו נוגע', (tester) async {
    WindowRole.isSecondary = true;

    final revision = await resetFromAnotherWindow(tester);

    expect(owner.revision, revision);
    expect(notifications.present, {reminderId('a')});
  });
}
