// טסטים לפוקוס של דיאלוג "מעבר לתאריך" בסרגל העליון:
// הוא צריך להיסגר רק במעבר אמיתי לרקע (paused), ולא כשהחלון מאבד פוקוס
// ל-OS (inactive/hidden) — כמו כל דיאלוג.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_date_picker_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_top_bar.dart';

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late SettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = SettingsBloc(repository: SettingsRepository())
      ..add(LoadSettings());
  });

  tearDown(() async {
    await settingsBloc.close();
  });

  Future<int> pumpAndDispatch(
    WidgetTester tester, {
    List<AppLifecycleState> states = const [],
    CalendarState? state,
    bool open = true,
  }) async {
    int closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: settingsBloc,
          child: Scaffold(
            body: CalendarTopBar(
              state: state ?? CalendarState.initial(),
              onJumpToToday: () {},
              onPreviousPeriod: () {},
              onNextPeriod: () {},
              onViewChanged: (_) {},
              activeSidePanelView: CalendarSidePanelView.events,
              isSidePanelVisible: false,
              isSettingsPanelOpen: false,
              onToggleTimesPanel: () {},
              onToggleEventsPanel: () {},
              onToggleSettingsPanel: () {},
              onPrint: () {},
              isJumpToDateSearchOpen: open,
              onToggleJumpToDateSearch: () {},
              onCloseJumpToDateSearch: () => closeCount++,
              parseInputDate: (_) => null,
              onJumpToDateSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    return closeCount;
  }

  testWidgets('נשאר פתוח כשהאפליקציה מאבדת פוקוס OS (inactive/hidden)', (
    tester,
  ) async {
    final closeCount = await pumpAndDispatch(
      tester,
      states: [AppLifecycleState.inactive, AppLifecycleState.hidden],
    );
    expect(closeCount, 0);
  });

  testWidgets('נסגר רק במעבר אמיתי לרקע (paused)', (tester) async {
    // מעבר תקין דורש שרשור: resumed → inactive → hidden → paused.
    final closeCount = await pumpAndDispatch(
      tester,
      states: [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ],
    );
    // רק paused סוגר — inactive/hidden שקדמו לו לא.
    expect(closeCount, 1);
  });

  testWidgets('היום מסומן בבורר ולא התאריך הנבחר בלוח (issue #2492)', (
    tester,
  ) async {
    final initial = CalendarState.initial();
    final today = initial.todayGregorianDate;
    // תאריך אחר באותו חודש, כדי שגם היום יוצג בבורר.
    final other = DateTime(
      today.year,
      today.month,
      today.day < 28 ? today.day + 1 : today.day - 1,
    );
    final state = initial.copyWith(
      selectedGregorianDate: other,
      calendarType: CalendarType.gregorian,
    );
    // החלונית נפתחת במעבר מסגור לפתוח.
    await pumpAndDispatch(tester, state: state, open: false);
    await pumpAndDispatch(tester, state: state);
    FontWeight? weightOf(DateTime date) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(CalendarDatePickerPanel),
            matching: find.text('${date.day}'),
          ),
        )
        .style
        ?.fontWeight;
    expect(weightOf(today), FontWeight.bold);
    expect(weightOf(other), FontWeight.normal);
  });
}
