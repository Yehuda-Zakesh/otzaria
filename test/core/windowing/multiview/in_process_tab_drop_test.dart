import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/cross_window_tab_drag.dart';
import 'package:otzaria/core/windowing/drag_preview_colors.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../../test_helpers/fake_view_window.dart';

class _RecordingTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _RecordingTabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));

  final List<TabsEvent> events = [];

  @override
  void add(TabsEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _RecordingNavigationBloc() : super(NavigationState.initial(false));

  final List<NavigationEvent> events = [];

  @override
  void add(NavigationEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOpener implements WindowOpener {
  final List<({OpenedTab? tab, ({int x, int y})? origin})> opened = [];

  @override
  Future<bool> openWindow({
    OpenedTab? tab,
    ({int x, int y})? origin,
    ({int left, int top, int width, int height})? bounds,
    bool inheritPlacement = true,
  }) async {
    opened.add((tab: tab, origin: origin));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// הערוץ מול ה-runner: מה שתחת הסמן, ורישום של כל קריאה עם הארגומנטים.
class _Runner {
  Map<String, Object?> target = const {'isSelf': false, 'isShellTray': false};

  /// מה שתחת הסמן כשהגרירה שנמסרה למערכת מסתיימת.
  Map<String, Object?> systemDrag = const {};
  final List<MethodCall> calls = [];

  void install() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
        calls.add(call);
        if (call.method == 'windowAtCursor') {
          return {'x': 300, 'y': 40, ...target};
        }
        if (call.method == 'dragOutToSystem') {
          return {
            'ran': true,
            'snapped': false,
            'left': 1100,
            'top': 1040,
            'width': 176,
            'height': 40,
            'x': 1200,
            'y': 1060,
            'isSelf': false,
            'isShellTray': false,
            ...systemDrag,
          };
        }
        if (call.method == 'openWindow') return true;
        return null;
      });

  void uninstall() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(MultiWindowService.channel, null);

  List<MethodCall> named(String method) =>
      calls.where((c) => c.method == method).toList();
}

/// יעד שהרצועה שלו מחשבת מיקום הכנסה [index] לכל גרירה שמעליה.
({InProcessTabDropTarget target, List<(OpenedTab, int?)> received}) _target(
  int index,
) {
  final state = ExternalTabDragState();
  state.drag.addListener(() {
    state.dropIndex.value = state.drag.value == null ? null : index;
  });
  final received = <(OpenedTab, int?)>[];
  return (
    target: InProcessTabDropTarget(
      dragState: state,
      devicePixelRatio: () => 1.5,
      receive: (tab, index) {
        received.add((tab, index));
        return true;
      },
    ),
    received: received,
  );
}

void main() {
  late _Runner runner;
  final screenCalls = <({int x, int y, double dpr, int? hwnd})>[];

  InProcessTabDrops makeDrops(ViewWindowRegistry registry) {
    screenCalls.clear();
    return InProcessTabDrops(
      registry: registry,
      screenToClient: (x, y, dpr, {hwnd}) async {
        screenCalls.add((x: x, y: y, dpr: dpr, hwnd: hwnd));
        return Offset(x / dpr, y / dpr);
      },
    );
  }

  setUp(() {
    MultiViewMode.debugOverride = true;
    MultiWindowService.debugSupportedOverride = true;
    runner = _Runner()..install();
  });

  tearDown(() {
    runner.uninstall();
    MultiViewMode.debugOverride = null;
    MultiWindowService.debugSupportedOverride = null;
    WindowOpener.debugOverride = null;
    AppWindowKeys.resetForTest();
  });

  group('InProcessTabDrops', () {
    testWidgets('HWND של חלון Dart → המשבצת שלו; משבצת אפיק → הראשי', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final a = windows.registry.open(size: const Size(800, 600))!;
      final b = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);

      expect(drops.resolve(hwnd: a.handle.hwnd), a.slot);
      expect(drops.resolve(hwnd: b.handle.hwnd, busSlot: 1), b.slot);
      // ה-HWND של הראשי אינו ברשימה; המשבצת שלו באפיק היא שמזהה אותו.
      expect(drops.resolve(hwnd: 4242, busSlot: 1), InProcessTabDrops.mainSlot);
      expect(drops.resolve(hwnd: 4242), isNull);
      expect(drops.resolve(), isNull);
      expect(drops.slotOf(a.id), a.slot);
      expect(drops.slotOf(AppWindowId.primary), 1);
      expect(drops.hwndOf(b.id), b.handle.hwnd);
      expect(drops.hwndOf(AppWindowId.primary), isNull);
    });

    testWidgets('dragOver ממיר מול ה-HWND של היעד ומחזיר את מיקום ההכנסה', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final a = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final t = _target(2);
      drops.register(a.id, t.target);

      expect(await drops.notifyDragOver(a.slot, 300, 60, 'לוח שנה'), 2);
      expect(screenCalls.single, (
        x: 300,
        y: 60,
        dpr: 1.5,
        hwnd: a.handle.hwnd,
      ));
      expect(
        t.target.dragState.drag.value,
        const ExternalTabDrag(title: 'לוח שנה', local: Offset(200, 40)),
      );

      drops.notifyDragLeave(a.slot);
      expect(t.target.dragState.drag.value, isNull);
      // חלון בלי יעד רשום אינו מקבל דבר.
      expect(await drops.notifyDragOver(9, 1, 1, 'x'), isNull);
    });

    testWidgets('העברה שולחת עותק למקום המדויק; בלי יעד — false', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final a = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final t = _target(0);
      drops.register(a.id, t.target);
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');

      expect(await drops.sendTabToWindow(a.slot, tab, index: 1), isTrue);
      final (copy, index) = t.received.single;
      expect(index, 1);
      expect(copy, isNot(same(tab)));
      expect(copy.title, 'לוח שנה');

      expect(await drops.sendTabToWindow(1, tab), isFalse);
      drops.unregister(a.id, t.target);
      expect(await drops.sendTabToWindow(a.slot, tab), isFalse);
    });
  });

  group('InProcessTabDropReceiver', () {
    Widget providers(
      _RecordingTabsBloc tabs,
      _RecordingNavigationBloc nav,
      Widget child,
    ) => MultiBlocProvider(
      providers: [
        BlocProvider<TabsBloc>.value(value: tabs),
        BlocProvider<NavigationBloc>.value(value: nav),
      ],
      child: child,
    );

    testWidgets('הראשי: נרשם, שומר את המצב הגלובלי, וקולט למקום ההכנסה', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final tabs = _RecordingTabsBloc();
      final nav = _RecordingNavigationBloc();
      late BuildContext inner;
      await tester.pumpWidget(
        providers(
          tabs,
          nav,
          InProcessTabDropReceiver(
            drops: drops,
            child: Builder(
              builder: (context) {
                inner = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(
        ExternalTabDragState.of(inner),
        same(ExternalTabDragState.current),
      );

      final tab = ToolTab(toolId: 'builtin.gematria', title: 'גימטריה');
      expect(await drops.sendTabToWindow(1, tab, index: 0), isTrue);
      final added = (tabs.events[0] as AddTab).tab;
      expect(added.title, 'גימטריה');
      expect(tabs.events.single, AddTab(added, index: 0));
      expect(nav.events.single, const NavigateToScreen(Screen.reading));
      await tester.pump();
      expect(runner.named('raiseSelf'), hasLength(1));

      // bloc היעד נסגר באמצע: לא נקלטה, והמקור שומר את הכרטיסיה.
      await tabs.close();
      expect(await drops.sendTabToWindow(1, tab), isFalse);
      expect(tabs.events, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      expect(await drops.sendTabToWindow(1, tab), isFalse);
      await nav.close();
    });

    testWidgets('חלון Dart: מצב גרירה משלו, וקליטה מביאה אותו לחזית', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final entry = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final tabs = _RecordingTabsBloc();
      final nav = _RecordingNavigationBloc();
      late BuildContext inner;
      await tester.pumpWidget(
        AppWindowScope(
          controller: entry.controller,
          geometry: entry.controller,
          keys: entry.keys,
          child: providers(
            tabs,
            nav,
            InProcessTabDropReceiver(
              drops: drops,
              child: Builder(
                builder: (context) {
                  inner = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      final state = ExternalTabDragState.of(inner);
      expect(state, isNot(same(ExternalTabDragState.current)));

      // הראשי אינו רשום, ולכן גרירה מעליו אינה נוגעת בחלון הזה.
      expect(await drops.notifyDragOver(1, 10, 10, 'x'), isNull);
      await drops.notifyDragOver(entry.slot, 10, 10, 'x');
      expect(state.drag.value?.title, 'x');
      expect(ExternalTabDragState.current.drag.value, isNull);

      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      expect(await drops.sendTabToWindow(entry.slot, tab), isTrue);
      expect(state.drag.value, isNull);
      expect(tabs.events.single, isA<AddTab>());
      await tester.pump();
      expect(windows.native.focused, [entry.handle.hwnd]);
      await tester.pumpWidget(const SizedBox());
      await tabs.close();
      await nav.close();
    });
  });

  group('CrossWindowTabDrag עם ריבוי תצוגות', () {
    const colors = DragPreviewColors(
      tab: Color(0xFF202020),
      border: Color(0xFF404040),
      text: Color(0xFFF0F0F0),
    );

    testWidgets('מהראשי לחלון Dart: ישירות, למקום שתחת הסמן', (tester) async {
      final windows = FakeViewWindows(tester);
      final view = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final t = _target(1);
      drops.register(view.id, t.target);
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {
        'hwnd': view.handle.hwnd,
        'isSelf': false,
        'isShellTray': false,
      };

      await CrossWindowTabDrag(
        inProcess: drops,
      ).handleDroppedOutside(tab, source);

      expect(t.received.single.$2, 1);
      expect(screenCalls.single.hwnd, view.handle.hwnd);
      expect(source.events.single, RemoveTab(tab));
      // הראשי אינו שולח selfHwnd, אבל מבקש את ה-HWND שתחת הסמן.
      expect(runner.named('windowAtCursor').single.arguments, isEmpty);
      await source.close();
    });

    testWidgets('מחלון Dart לראשי: selfHwnd נשלח, והראשי מזוהה במשבצת', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final view = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final main = _target(3);
      drops.register(AppWindowId.primary, main.target);
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source, sourceWindow: view.id);
      runner.target = {
        'slot': 1,
        'hwnd': 777,
        'isSelf': false,
        'isShellTray': false,
      };
      drag.end();

      await drag.handleDroppedOutside(tab, source);

      expect(main.received.single.$2, 3);
      expect(screenCalls.single.hwnd, isNull);
      expect(source.events.single, RemoveTab(tab));
      expect(
        (runner.named('beginTabDrag').single.arguments as Map)['sourceHwnd'],
        view.handle.hwnd,
      );
      expect(
        runner.named('windowAtCursor').map((c) => c.arguments),
        everyElement({'selfHwnd': view.handle.hwnd}),
      );
      drag.dispose();
      await source.close();
    });

    testWidgets('שחרור מעל חלון המקור (Dart) מבוטל גם בלי משבצת אפיק', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final view = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final t = _target(0);
      drops.register(view.id, t.target);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source, sourceWindow: view.id);
      runner.target = {
        'hwnd': view.handle.hwnd,
        'isSelf': false,
        'isShellTray': false,
      };
      drag.end();

      await drag.handleDroppedOutside(tab, source);

      expect(source.events, isEmpty);
      expect(t.received, isEmpty);
      expect(opener.opened, isEmpty);
      drag.dispose();
      await source.close();
    });

    testWidgets('שחרור על שולחן העבודה פותח חלון Dart בנקודת השחרור', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {'hwnd': 31337, 'isSelf': false, 'isShellTray': false};

      await CrossWindowTabDrag(
        inProcess: drops,
      ).handleDroppedOutside(tab, source);

      expect(opener.opened.single.tab, same(tab));
      expect(opener.opened.single.origin, (x: 300, y: 40));
      expect(source.events.single, RemoveTab(tab));
      // ה-runner אינו מכיר חלונות Dart, ולכן הרוח מוסתרת כאן.
      expect(runner.named('endTabDrag'), hasLength(1));
      await source.close();
    });

    testWidgets('שחרור מחוץ לאזור העבודה (שורת משימות) מבוטל', (tester) async {
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      // מחלקת שורת המשימות לא זוהתה; רק אזור העבודה מעיד עליה.
      runner.target = {
        'hwnd': 31337,
        'isSelf': false,
        'isShellTray': false,
        'inWorkArea': false,
      };

      await CrossWindowTabDrag(
        inProcess: drops,
      ).handleDroppedOutside(tab, source);

      expect(opener.opened, isEmpty);
      expect(source.events, isEmpty);
      expect(runner.named('endTabDrag'), hasLength(1));
      await source.close();
    });

    testWidgets('גרירה שנמסרה למערכת ושוחררה מעל שורת המשימות מבוטלת', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      var cancelled = 0;
      // הסמן יצא מהחלון, והגרירה נמסרת ל-Windows.
      runner.target = {'hwnd': 31337, 'isSelf': false, 'isShellTray': false};
      runner.systemDrag = {'hwnd': 4242, 'inWorkArea': false};
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source, cancelDrag: () => cancelled++);

      await tester.pump(const Duration(seconds: 1));

      expect(runner.named('dragOutToSystem'), hasLength(1));
      expect(cancelled, 1);
      expect(opener.opened, isEmpty);
      expect(source.events, isEmpty);
      expect(runner.named('endTabDrag'), isNotEmpty);
      drag.dispose();
      await source.close();
    });

    testWidgets(
      'גרירה למערכת: סמן שנכלא בקצה אזור העבודה מעל חלון אוצריא — מבוטלת',
      (tester) async {
        final windows = FakeViewWindows(tester);
        final view = windows.registry.open(size: const Size(800, 600))!;
        final drops = makeDrops(windows.registry);
        final t = _target(2);
        drops.register(view.id, t.target);
        final opener = _FakeOpener();
        WindowOpener.debugOverride = opener;
        final source = _RecordingTabsBloc();
        final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
        // שחרור ב-(1250,1060) נמדד ב-(1250,1031), מעל חלון שכולו מעל השורה.
        runner.target = {'hwnd': 31337, 'isSelf': false, 'isShellTray': false};
        runner.systemDrag = {
          'x': 1250,
          'y': 1031,
          'hwnd': view.handle.hwnd,
          'inWorkArea': true,
          'atTaskbarEdge': true,
        };
        final drag = CrossWindowTabDrag(inProcess: drops)
          ..begin(tab, colors, tabsBloc: source);

        await tester.pump(const Duration(seconds: 1));

        expect(runner.named('dragOutToSystem'), hasLength(1));
        expect(t.received, isEmpty);
        expect(opener.opened, isEmpty);
        expect(source.events, isEmpty);
        expect(runner.named('endTabDrag'), isNotEmpty);
        drag.dispose();
        await source.close();
      },
    );

    testWidgets(
      'גרירה למערכת: סמן שנכלא בקצה אזור העבודה מעל שולחן העבודה — מבוטלת',
      (tester) async {
        final windows = FakeViewWindows(tester);
        final drops = makeDrops(windows.registry);
        final opener = _FakeOpener();
        WindowOpener.debugOverride = opener;
        final source = _RecordingTabsBloc();
        final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
        runner.target = {'hwnd': 31337, 'isSelf': false, 'isShellTray': false};
        runner.systemDrag = {
          'y': 1031,
          'hwnd': 4242,
          'inWorkArea': true,
          'atTaskbarEdge': true,
        };
        final drag = CrossWindowTabDrag(inProcess: drops)
          ..begin(tab, colors, tabsBloc: source);

        await tester.pump(const Duration(seconds: 1));

        expect(runner.named('dragOutToSystem'), hasLength(1));
        expect(opener.opened, isEmpty);
        expect(source.events, isEmpty);
        drag.dispose();
        await source.close();
      },
    );

    testWidgets('גרירה למערכת שהוצמדה (Snap) אינה מבוטלת בקצה אזור העבודה', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {'hwnd': 31337, 'isSelf': false, 'isShellTray': false};
      runner.systemDrag = {
        'snapped': true,
        'hwnd': 4242,
        'atTaskbarEdge': true,
      };
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source);

      await tester.pump(const Duration(seconds: 1));

      expect(opener.opened, hasLength(1));
      expect(source.events.single, RemoveTab(tab));
      drag.dispose();
      await source.close();
    });

    testWidgets('חלון אוצריא מחוץ לאזור העבודה (מסך מלא) עדיין קולט', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final view = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final t = _target(2);
      drops.register(view.id, t.target);
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {
        'hwnd': view.handle.hwnd,
        'isSelf': false,
        'isShellTray': false,
        'inWorkArea': false,
      };

      await CrossWindowTabDrag(
        inProcess: drops,
      ).handleDroppedOutside(tab, source);

      expect(t.received.single.$2, 2);
      expect(source.events.single, RemoveTab(tab));
      await source.close();
    });

    testWidgets('בלי הדגל: אותן קריאות כמו היום, ושום העברה ישירה', (
      tester,
    ) async {
      MultiViewMode.debugOverride = false;
      final windows = FakeViewWindows(tester);
      final view = windows.registry.open(size: const Size(800, 600))!;
      final drops = makeDrops(windows.registry);
      final t = _target(0);
      drops.register(view.id, t.target);
      // מודל A פותח מנוע דרך ה-runner; כאן רק נבדק שהשחרור הגיע לפתיחה.
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source, sourceWindow: view.id);
      runner.target = {
        'hwnd': view.handle.hwnd,
        'isSelf': false,
        'isShellTray': false,
      };
      drag.end();

      await drag.handleDroppedOutside(tab, source);

      expect(t.received, isEmpty);
      expect(opener.opened, hasLength(1));
      expect(source.events.single, RemoveTab(tab));
      // הרוח נשארת: ה-runner מסתיר אותה כשהמנוע החדש נחשף.
      expect(runner.named('endTabDrag'), isEmpty);
      expect(screenCalls, isEmpty);
      expect(
        runner.named('windowAtCursor').map((c) => c.arguments),
        allOf(isNotEmpty, everyElement(isNull)),
      );
      expect(
        (runner.named('beginTabDrag').single.arguments as Map).containsKey(
          'sourceHwnd',
        ),
        isFalse,
      );
      drag.dispose();
      await source.close();
    });

    testWidgets('בלי הדגל: גרירה למערכת שנכלאה בקצה אזור העבודה מבוטלת', (
      tester,
    ) async {
      MultiViewMode.debugOverride = false;
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      var cancelled = 0;
      // מודל A: שחרור ב-(1000,1060) נמדד ב-(1000,1031) מעל שולחן העבודה.
      runner.target = {'isSelf': false, 'isShellTray': false};
      runner.systemDrag = {
        'y': 1031,
        'inWorkArea': true,
        'atTaskbarEdge': true,
      };
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source, cancelDrag: () => cancelled++);

      await tester.pump(const Duration(seconds: 1));

      expect(runner.named('dragOutToSystem').single.arguments, isNull);
      expect(cancelled, 1);
      expect(opener.opened, isEmpty);
      expect(source.events, isEmpty);
      expect(runner.named('endTabDrag'), isNotEmpty);
      drag.dispose();
      await source.close();
    });

    testWidgets('בלי הדגל: גרירה למערכת שהוצמדה בקצה אזור העבודה נפתחת', (
      tester,
    ) async {
      MultiViewMode.debugOverride = false;
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {'isSelf': false, 'isShellTray': false};
      runner.systemDrag = {'snapped': true, 'atTaskbarEdge': true};
      final drag = CrossWindowTabDrag(inProcess: drops)
        ..begin(tab, colors, tabsBloc: source);

      await tester.pump(const Duration(seconds: 1));

      expect(opener.opened, hasLength(1));
      expect(source.events.single, RemoveTab(tab));
      drag.dispose();
      await source.close();
    });

    testWidgets('בלי הדגל: שחרור על שולחן העבודה מחוץ לאזור העבודה מבוטל', (
      tester,
    ) async {
      MultiViewMode.debugOverride = false;
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {
        'isSelf': false,
        'isShellTray': false,
        'inWorkArea': false,
      };

      await CrossWindowTabDrag(
        inProcess: drops,
      ).handleDroppedOutside(tab, source);

      expect(opener.opened, isEmpty);
      expect(source.events, isEmpty);
      expect(runner.named('endTabDrag'), hasLength(1));
      await source.close();
    });

    testWidgets('בלי הדגל: חלון אוצריא מחוץ לאזור העבודה (מסך מלא) קולט', (
      tester,
    ) async {
      MultiViewMode.debugOverride = false;
      final windows = FakeViewWindows(tester);
      final drops = makeDrops(windows.registry);
      final opener = _FakeOpener();
      WindowOpener.debugOverride = opener;
      final source = _RecordingTabsBloc();
      final tab = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      runner.target = {
        'slot': 1,
        'isSelf': false,
        'isShellTray': false,
        'inWorkArea': false,
      };

      // ההעברה עצמה עוברת באפיק, שאינו קיים כאן; נבדק רק שאין ביטול.
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        await CrossWindowTabDrag(
          inProcess: drops,
        ).handleDroppedOutside(tab, source);
      } finally {
        debugPrint = original;
      }

      expect(opener.opened, isEmpty);
      expect(logs, isNot(contains(contains('שורת המשימות'))));
      await source.close();
    });
  });
}
