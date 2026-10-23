import 'package:otzaria/app_scope/app_scope_providers.dart';
import 'package:otzaria/app_scope/window_scope_providers.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../../helpers/memory_settings_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';

/// מצב UI שהיה סטטי ל-isolate מוחזק עכשיו לכל [AppWindowKeys] — שני חלונות
/// באותו isolate לא דורסים זה את ההודעה, החלונית או ה-callback של זה.
void main() {
  final original = AppWindowKeys.current;
  tearDown(() => AppWindowKeys.activate(original));

  final window = _FakeWindow();

  Widget windowTree(AppWindowKeys keys, String label) => AppWindowScope(
    controller: window,
    geometry: window,
    keys: keys,
    child: Builder(
      builder: (context) => MaterialApp(
        navigatorKey: AppWindowKeys.of(context).navigator,
        home: Scaffold(body: Text(label)),
      ),
    ),
  );

  Future<void> pumpTwoWindows(
    WidgetTester tester,
    AppWindowKeys a,
    AppWindowKeys b,
  ) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          Expanded(child: windowTree(a, 'חלון א')),
          Expanded(child: windowTree(b, 'חלון ב')),
        ],
      ),
    ),
  );

  Finder inWindow(AppWindowKeys keys, String text) => find.descendant(
    of: find.byKey(keys.navigator),
    matching: find.text(text),
  );

  group('UiSnack', () {
    testWidgets('הודעה בחלון אחד אינה מסירה את ההודעה בחלון האחר', (
      tester,
    ) async {
      final a = AppWindowKeys();
      final b = AppWindowKeys();
      await pumpTwoWindows(tester, a, b);

      AppWindowKeys.activate(a);
      UiSnack.showChecking('בדיקה בא');
      await tester.pump();
      AppWindowKeys.activate(b);
      UiSnack.showChecking('בדיקה בב');
      await tester.pump();

      expect(inWindow(a, 'בדיקה בא'), findsOneWidget);
      expect(inWindow(b, 'בדיקה בב'), findsOneWidget);

      // hide() בלי בעלים — רק החלון הנוכחי.
      UiSnack.hide();
      await tester.pump();
      expect(inWindow(b, 'בדיקה בב'), findsNothing);
      expect(inWindow(a, 'בדיקה בא'), findsOneWidget);

      AppWindowKeys.activate(a);
      UiSnack.hide();
      await tester.pump();
      expect(inWindow(a, 'בדיקה בא'), findsNothing);
    });

    testWidgets('hide(owner:) מוצא את ההודעה גם כשחלון אחר נוכחי', (
      tester,
    ) async {
      final a = AppWindowKeys();
      final b = AppWindowKeys();
      await pumpTwoWindows(tester, a, b);

      final owner = Object();
      AppWindowKeys.activate(a);
      UiSnack.showChecking('של בעלים', owner: owner);
      await tester.pump();
      expect(inWindow(a, 'של בעלים'), findsOneWidget);

      AppWindowKeys.activate(b);
      UiSnack.hide(owner: owner);
      await tester.pump();
      expect(find.text('של בעלים'), findsNothing);
    });
  });

  group('LinkPreviewOverlay', () {
    tearDown(() {
      LinkPreviewOverlay.dismiss();
    });

    void showIn(WidgetTester tester, String windowLabel, String content) {
      LinkPreviewOverlay.showContent(
        tester.element(find.text(windowLabel)),
        contentBuilder: (_) => Text(content),
        globalPosition: tester.getCenter(find.text(windowLabel)),
      );
    }

    testWidgets('חלונית בחלון אחד אינה נסגרת כשנפתחת חלונית בחלון אחר', (
      tester,
    ) async {
      final a = AppWindowKeys();
      final b = AppWindowKeys();
      await pumpTwoWindows(tester, a, b);

      showIn(tester, 'חלון א', 'תצוגה בא');
      await tester.pump();
      showIn(tester, 'חלון ב', 'תצוגה בב');
      await tester.pump();

      expect(inWindow(a, 'תצוגה בא'), findsOneWidget);
      expect(inWindow(b, 'תצוגה בב'), findsOneWidget);

      // dismiss() בלי מזהה — החלון הנוכחי בלבד.
      AppWindowKeys.activate(b);
      LinkPreviewOverlay.dismiss();
      await tester.pump();
      expect(inWindow(b, 'תצוגה בב'), findsNothing);
      expect(inWindow(a, 'תצוגה בא'), findsOneWidget);

      AppWindowKeys.activate(a);
      LinkPreviewOverlay.dismiss();
      await tester.pump();
      expect(find.text('תצוגה בא'), findsNothing);
    });

    testWidgets('dismiss עם מזהה סוגר את החלונית שלו בכל חלון', (
      tester,
    ) async {
      final a = AppWindowKeys();
      final b = AppWindowKeys();
      await pumpTwoWindows(tester, a, b);

      final rect = tester.getRect(find.text('חלון א'));
      final token = LinkPreviewOverlay.showBesideMenuItem(
        tester.element(find.text('חלון א')),
        contentBuilder: (_) => const Text('ליד תפריט'),
        itemGlobalRect: rect,
        minWidth: 100,
      );
      await tester.pump();
      expect(token, isNotNull);
      expect(inWindow(a, 'ליד תפריט'), findsOneWidget);

      AppWindowKeys.activate(b);
      LinkPreviewOverlay.dismiss(token: token);
      await tester.pump();
      expect(find.text('ליד תפריט'), findsNothing);
    });
  });

  testWidgets('סיום ריחוף סוגר את החלונית של החלון המקורי אחרי שינוי פוקוס', (
    tester,
  ) async {
    final a = AppWindowKeys();
    final b = AppWindowKeys();
    await pumpTwoWindows(tester, a, b);
    for (final keys in [a, b]) {
      final label = identical(keys, a) ? 'חלון א' : 'חלון ב';
      LinkPreviewOverlay.showContent(
        tester.element(find.text(label)),
        contentBuilder: (_) => Text(identical(keys, a) ? 'ריחוף א' : 'ריחוף ב'),
        globalPosition: tester.getCenter(find.text(label)),
        hoverMode: true,
      );
    }
    await tester.pump();
    AppWindowKeys.activate(b);
    LinkPreviewOverlay.scheduleHide(a);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(inWindow(a, 'ריחוף א'), findsNothing);
    expect(inWindow(b, 'ריחוף ב'), findsOneWidget);
    LinkPreviewOverlay.dismiss(window: b);
    await tester.pump();
  });

  testWidgets('השלמת הודעה אסינכרונית נשארת בחלון שהתחיל אותה', (tester) async {
    final a = AppWindowKeys();
    final b = AppWindowKeys();
    await pumpTwoWindows(tester, a, b);
    final owner = Object();
    AppWindowKeys.activate(b);
    UiSnack.showChecking('מעביר בא', owner: owner, window: a);
    UiSnack.showChecking('בדיקה בב', window: b);
    await tester.pump();
    await Future<void>.value();
    UiSnack.hide(owner: owner);
    UiSnack.showSuccess('הועבר בא', window: a);
    await tester.pump();
    expect(inWindow(a, 'הועבר בא'), findsOneWidget);
    expect(inWindow(b, 'בדיקה בב'), findsOneWidget);
    UiSnack.hide(window: a);
    UiSnack.hide(window: b);
    await tester.pump();
  });

  testWidgets('סגירת היקף חלון מנקה רק את החלוניות וההודעות שלו', (
    tester,
  ) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final a = AppWindowKeys();
    final b = AppWindowKeys();
    var dismissedB = 0;
    Widget tree(bool showB) => AppScopeProviders(
      settingsRepository: SettingsRepository(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            for (final keys in [a, if (showB) b])
              Expanded(
                key: ObjectKey(keys),
                child: AppWindowScope(
                  controller: window,
                  geometry: window,
                  keys: keys,
                  child: WindowScopeProviders(
                    historyRepository: HistoryRepository(),
                    child: MaterialApp(
                      navigatorKey: keys.navigator,
                      home: Scaffold(
                        body: Text(identical(keys, a) ? 'א' : 'ב'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(tree(true));
    for (final keys in [a, b]) {
      UiSnack.showChecking(
        identical(keys, a) ? 'ממתין בא' : 'ממתין בב',
        window: keys,
      );
      final context = tester.element(
        inWindow(keys, identical(keys, a) ? 'א' : 'ב'),
      );
      LinkPreviewOverlay.showContent(
        context,
        contentBuilder: (_) =>
            Text(identical(keys, a) ? 'חלונית א' : 'חלונית ב'),
        globalPosition: const Offset(40, 40),
        onDismissed: identical(keys, b) ? () => dismissedB++ : null,
      );
    }
    await tester.pump();
    AppWindowKeys.activate(a);
    await tester.pumpWidget(tree(false));
    expect(dismissedB, 1);
    expect(inWindow(a, 'חלונית א'), findsOneWidget);
    expect(inWindow(a, 'ממתין בא'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  group('משגרי כלים ודפי תוספים', () {
    test('ה-callback הרשום של כל חלון נפרד, וביטול רישום אינו נוגע באחר', () {
      final a = AppWindowKeys();
      final b = AppWindowKeys();
      final tools = ToolsLauncherController.instance;
      final pages = PluginPageLauncher.instance;
      final opened = <String>[];
      void openA() => opened.add('tools-a');
      void openB() => opened.add('tools-b');
      void pageA(String id) => opened.add('a:$id');
      void pageB(String id) => opened.add('b:$id');

      tools.register(a, openA);
      tools.register(b, openB);
      pages.register(a, pageA);
      pages.register(b, pageB);
      addTearDown(() {
        tools.unregister(a, openA);
        tools.unregister(b, openB);
        pages.unregister(a, pageA);
        pages.unregister(b, pageB);
      });

      AppWindowKeys.activate(a);
      tools.open();
      pages.open('p1');
      AppWindowKeys.activate(b);
      tools.open();
      pages.open('p2');
      expect(opened, ['tools-a', 'a:p1', 'tools-b', 'b:p2']);

      // סגירת חלון א אינה מאפסת את ב.
      tools.unregister(a, openA);
      pages.unregister(a, pageA);
      opened.clear();
      tools.open();
      pages.open('p3');
      expect(opened, ['tools-b', 'b:p3']);

      AppWindowKeys.activate(a);
      expect(tools.opener, isNull);
      expect(pages.navigator, isNull);
    });

    test('unregister של callback שהוחלף אינו מוחק את המחליף', () {
      final a = AppWindowKeys();
      final tools = ToolsLauncherController.instance;
      void first() {}
      void second() {}
      tools.register(a, first);
      tools.register(a, second);
      addTearDown(() => tools.unregister(a, second));

      tools.unregister(a, first);
      AppWindowKeys.activate(a);
      expect(tools.opener, same(second));
    });
  });
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}
