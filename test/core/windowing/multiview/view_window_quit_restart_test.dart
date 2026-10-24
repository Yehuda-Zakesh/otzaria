import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/multiview/view_window_scope.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';

import '../../../helpers/memory_settings_cache.dart';
import '../../../test_helpers/fake_view_window.dart';

/// G4/G12: אתחול מחדש מרכיב מחדש את חלונות ה-Dart, ושטיפת סיום הסשן ויציאה
/// מכל החלונות שומרות את הסשן של כל אחד מהם להפעלה הבאה.
void main() {
  late Directory tmp;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('view_window_quit_');
    AppPaths.debugProfileDataRootPath = tmp.path;
    UserStateDatabase.instance.overridePath('${tmp.path}/user_state.db');
    MultiViewMode.debugOverride = true;
  });

  tearDown(() {
    MultiViewMode.debugOverride = false;
    AppPaths.debugProfileDataRootPath = null;
    AppWindowKeys.resetForTest();
    LastActiveWindow.resetForTest();
    UserStateDatabase.instance.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows עלול להחזיק את הקובץ עוד רגע; תיקיית temp בלבד.
    }
  });

  /// כמו ב-main: RestartWidget מעל AppBootstrap, שמציג מסך פתיחה עד סוף האתחול.
  Future<Map<int, BuildContext>> pumpApp(
    WidgetTester tester,
    ViewWindowRegistry registry, {
    bool bootstrapGap = true,
  }) async {
    final contexts = <int, BuildContext>{};
    await tester.pumpWidget(
      RestartWidget(
        child: _Bootstrap(
          gap: bootstrapGap,
          child: AppScopeProviders(
            settingsRepository: SettingsRepository(),
            child: MultiViewHost(
              registry: registry,
              contentBuilder: (context, entry) => ViewWindowScope(
                entry: entry,
                child: Builder(
                  builder: (context) => MaterialApp(
                    navigatorKey: AppWindowKeys.of(context).navigator,
                    home: Builder(
                      builder: (context) {
                        contexts[entry.slot] = context;
                        // כמו App: ה-TabsBloc העצל נוצר כשהחלון נבנה.
                        context.read<TabsBloc>();
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return contexts;
  }

  Future<List<String>> savedTitles(int slot) async {
    final session = await WindowSessionStore.instance.load(slot);
    if (session == null) return const [];
    return [
      for (final tab in jsonDecode(session.tabsJson) as List)
        (tab as Map)['title'] as String,
    ];
  }

  Future<(ViewWindowEntry, ViewWindowEntry)> openTwo(
    WidgetTester tester,
    FakeViewWindows windows,
  ) async {
    final a = windows.registry.open(
      size: const Size(800, 600),
      initialTab: ToolTab(toolId: 'calendar', title: 'לוח שנה'),
    )!;
    final b = windows.registry.open(
      size: const Size(800, 600),
      initialTab: ToolTab(toolId: 'notes', title: 'הערות'),
    )!;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return (a, b);
  }

  testWidgets('אתחול מחדש מחלון Dart מרכיב מחדש את כל החלונות בלי לסגור', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    final contexts = await pumpApp(tester, windows.registry);
    final (a, b) = await openTwo(tester, windows);
    final oldTabsA = contexts[a.slot]!.read<TabsBloc>();
    final oldTabsB = contexts[b.slot]!.read<TabsBloc>();
    final oldHandler = a.closeHandler;
    expect(oldHandler, isNotNull);
    expect(await savedTitles(a.slot), ['לוח שנה']);

    AppQuit.restartAll(contexts[a.slot]!);
    await tester.pump();
    // מסך הפתיחה: עצי החלונות פורקו, החלונות עצמם נשארו.
    expect(find.byType(View), findsOneWidget);
    expect(a.closeHandler, isNull);
    expect(oldTabsA.isClosed, isTrue);
    expect(oldTabsB.isClosed, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    // החלונות עצמם שורדים: אותן רשומות, בלי הריסה.
    expect(windows.registry.windows, [a, b]);
    expect(windows.stubOf(a).destroyed, isFalse);
    expect(windows.stubOf(b).destroyed, isFalse);
    expect(find.byType(View), findsNWidgets(3));
    // העצים נבנו מחדש עם blocs חדשים.
    final tabsA = contexts[a.slot]!.read<TabsBloc>();
    final tabsB = contexts[b.slot]!.read<TabsBloc>();
    expect(identical(tabsA, oldTabsA), isFalse);
    expect(identical(tabsB, oldTabsB), isFalse);
    // הכרטיסיות נטענות מהסשן של כל חלון; כרטיסיית הפתיחה אינה מתווספת שוב.
    expect(tabsA.state.tabs.map((t) => t.title), ['לוח שנה']);
    expect(tabsB.state.tabs.map((t) => t.title), ['הערות']);
    // מסלול הסגירה מחובר לעץ החדש, והסשן עוד שייך לחלון.
    expect(a.closeHandler, isNotNull);
    expect(identical(a.closeHandler, oldHandler), isFalse);
    expect(a.tabsSession.slot, a.slot);
    expect(AppWindowKeys.of(contexts[b.slot]!), same(b.keys));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('גם בלי מסך הפתיחה, עצי החלונות נבנים מחדש', (tester) async {
    // ל-View יש GlobalKey לפי ה-FlutterView: באותו פריים הוא מועבר, ורק המפתח
    // של MultiViewHost מכריח לבנות מחדש את העץ שבתוכו.
    final windows = FakeViewWindows(tester);
    final contexts = await pumpApp(
      tester,
      windows.registry,
      bootstrapGap: false,
    );
    final (a, _) = await openTwo(tester, windows);
    final oldTabsA = contexts[a.slot]!.read<TabsBloc>();
    expect(await savedTitles(a.slot), ['לוח שנה']);

    AppQuit.restartAll(contexts[a.slot]!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(oldTabsA.isClosed, isTrue);
    final tabsA = contexts[a.slot]!.read<TabsBloc>();
    // הסשן לא נדרס בסגירת ה-bloc הישן, והחדש טוען ממנו.
    expect(await savedTitles(a.slot), ['לוח שנה']);
    expect(identical(tabsA, oldTabsA), isFalse);
    expect(tabsA.state.tabs.map((t) => t.title), ['לוח שנה']);
    expect(windows.stubOf(a).destroyed, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('אתחול מחדש משחרר את קורא הטקסט של העץ הקודם', (tester) async {
    final windows = FakeViewWindows(tester);
    final contexts = await pumpApp(tester, windows.registry);
    final tab = TextBookTab(book: TextBook(title: 'probe'), index: 0);
    final entry = windows.registry.open(
      size: const Size(800, 600),
      initialTab: tab,
    )!;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final oldTabs = contexts[entry.slot]!.read<TabsBloc>();
    expect(oldTabs.state.tabs.single, same(tab));
    final oldReader = tab.bloc;
    expect(oldReader.isClosed, isFalse);
    AppQuit.restartAll(contexts[entry.slot]!);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(oldTabs.isClosed, isTrue);
    expect(
      contexts[entry.slot]!.read<TabsBloc>().state.tabs.single,
      isNot(same(tab)),
    );
    expect(oldReader.isClosed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('שטיפת סיום הסשן כותבת את הסשן של כל חלון Dart', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    await pumpApp(tester, windows.registry);
    final (a, b) = await openTwo(tester, windows);
    // כאילו השמירה הרציפה לא הספיקה: רק השטיפה יכולה להחזיר את השורות.
    await WindowSessionStore.instance.delete(a.slot);
    await WindowSessionStore.instance.delete(b.slot);
    expect(await savedTitles(a.slot), isEmpty);

    const channel = MethodChannel('otzaria/process_control');
    var flushDone = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'sessionEndFlushDone') flushDone++;
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      channel.setMethodCallHandler(null);
    });
    AppWindowListener();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('prepareForSessionEnd')),
      (_) {},
    );
    for (var i = 0; i < 10 && flushDone == 0; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(flushDone, 1);
    expect(await savedTitles(a.slot), ['לוח שנה']);
    expect(await savedTitles(b.slot), ['הערות']);
    // השטיפה אינה סוגרת חלון.
    expect(windows.registry.windows, [a, b]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('יציאה מכל החלונות: נהרסים, והסשנים נשארים להפעלה הבאה', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    await pumpApp(tester, windows.registry);
    final (a, b) = await openTwo(tester, windows);
    final opener = ViewWindowOpener(
      registry: windows.registry,
      native: windows.native,
    );

    opener.destroyAllForQuit();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(windows.stubOf(a).destroyed, isTrue);
    expect(windows.stubOf(b).destroyed, isTrue);
    expect(windows.registry.windows, isEmpty);
    expect(find.byType(View), findsOneWidget);
    // פירוק העצים אינו מוחק ואינו דורס: סגירה לא-מכוונת אינה "סגירת חלון".
    expect(await savedTitles(a.slot), ['לוח שנה']);
    expect(await savedTitles(b.slot), ['הערות']);
    expect(opener.closedCountForTest, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

/// כמו AppBootstrap: אחרי כל אתחול מחדש, פריים של מסך פתיחה לפני העץ.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.gap, required this.child});

  final bool gap;
  final Widget child;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late bool _ready = !widget.gap;

  @override
  void initState() {
    super.initState();
    if (_ready) return;
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}
