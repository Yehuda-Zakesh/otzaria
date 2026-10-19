import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/calendar_screen.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../test_helpers/memory_cache_provider.dart';

/// issue #1353 — יום שנבחר בלוח נשאר "התאריך הנבחר" גם אחרי סגירת לשונית
/// הלוח, ותוספים שמבקשים את התאריך מה-API קיבלו אותו במקום את היום.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('סגירת לשונית הלוח (issue #1353)', () {
    late CalendarCubit calendarCubit;
    late SettingsBloc settingsBloc;

    setUp(() {
      settingsBloc = SettingsBloc(repository: SettingsRepository())
        ..add(LoadSettings());
      calendarCubit = CalendarCubit(
        notificationService: _FakeNotificationService(),
        googleCalendarService: _FakeGoogleCalendarService(),
      );
    });

    tearDown(() {
      settingsBloc.close();
      calendarCubit.close();
    });

    testWidgets('התאריך הנבחר חוזר להיום כשהלוח נסגר', (tester) async {
      Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settingsBloc),
              BlocProvider.value(value: calendarCubit),
            ],
            child: child,
          ),
        ),
      );

      await tester.pumpWidget(host(const CalendarWidget()));
      await tester.pumpAndSettle();

      // "היום" של הלוח מתחשב במעבר היום ההלכתי (אחרי צאת הכוכבים זהו כבר
      // מחר) — נקודת ההשוואה היא מה שכפתור "היום" של הלוח עצמו נותן.
      calendarCubit.jumpToToday();
      await tester.pumpAndSettle();
      final today = calendarCubit.state.selectedGregorianDate;
      final shifted = today.add(const Duration(days: 40));
      calendarCubit.jumpToDate(shifted);
      await tester.pumpAndSettle();
      expect(calendarCubit.state.selectedGregorianDate, shifted);

      // סגירת הלשונית — הלוח מוסר מהעץ.
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(
        DateUtils.dateOnly(calendarCubit.state.selectedGregorianDate),
        DateUtils.dateOnly(today),
      );
    });

    testWidgets('סגירת מופע אחד לא מאפסת מופע נוסף שעדיין פתוח', (
      tester,
    ) async {
      Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: settingsBloc),
              BlocProvider.value(value: calendarCubit),
            ],
            child: child,
          ),
        ),
      );

      var isFirstCalendarOpen = true;
      late StateSetter setHostState;
      const first = CalendarWidget(key: ValueKey('first-calendar'));
      const second = CalendarWidget(key: ValueKey('second-calendar'));
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Stack(children: [if (isFirstCalendarOpen) first, second]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shifted = calendarCubit.state.selectedGregorianDate.add(
        const Duration(days: 40),
      );
      calendarCubit.jumpToDate(shifted);
      await tester.pumpAndSettle();

      setHostState(() => isFirstCalendarOpen = false);
      await tester.pumpAndSettle();

      expect(calendarCubit.state.selectedGregorianDate, shifted);
    });
  });
}

class _FakeNotificationService implements NotificationService {
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get hasPermissions => true;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<bool> checkPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> forceRequestPermissions() async => true;

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {}

  @override
  Future<void> cancelNotification(int id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeGoogleCalendarService extends GoogleCalendarService {
  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<void> signOut() async {}

  @override
  Future<GoogleCalendarApiClient?> getApiClient({
    bool interactive = false,
  }) async => null;
}
