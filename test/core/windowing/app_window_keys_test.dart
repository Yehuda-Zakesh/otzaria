import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';

/// שני חלונות באותו isolate חייבים מפתחות נפרדים — אחרת GlobalKey מתנגש
/// והודעות של חלון אחד מוצגות באחר.
void main() {
  final original = AppWindowKeys.current;
  tearDown(() {
    UiSnack.hide();
    AppWindowKeys.activate(original);
  });

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

  testWidgets('שני scopes באותו עץ פותרים Navigator נפרד', (tester) async {
    final a = AppWindowKeys();
    final b = AppWindowKeys();
    await pumpTwoWindows(tester, a, b);

    expect(AppWindowKeys.of(tester.element(find.text('חלון א'))), same(a));
    expect(AppWindowKeys.of(tester.element(find.text('חלון ב'))), same(b));
    expect(a.navigator.currentState, isNotNull);
    expect(b.navigator.currentState, isNotNull);
    expect(a.navigator.currentState, isNot(same(b.navigator.currentState)));
  });

  testWidgets('UiSnack מוצג ב-Navigator של החלון הנוכחי', (tester) async {
    final a = AppWindowKeys();
    final b = AppWindowKeys();
    await pumpTwoWindows(tester, a, b);

    Finder inWindow(AppWindowKeys keys, String text) => find.descendant(
      of: find.byKey(keys.navigator),
      matching: find.text(text),
    );

    AppWindowKeys.activate(b);
    UiSnack.show('הודעה לב');
    await tester.pump();
    expect(inWindow(b, 'הודעה לב'), findsOneWidget);
    expect(inWindow(a, 'הודעה לב'), findsNothing);

    UiSnack.hide();
    await tester.pump();
    AppWindowKeys.activate(a);
    UiSnack.show('הודעה לא');
    await tester.pump();
    expect(inWindow(a, 'הודעה לא'), findsOneWidget);
    expect(inWindow(b, 'הודעה לא'), findsNothing);

    UiSnack.hide();
    await tester.pump();
  });

  testWidgets('בלי מפתחות ב-scope, או בלי scope — החלון הנוכחי', (
    tester,
  ) async {
    late AppWindowKeys withoutKeys;
    late AppWindowKeys withoutScope;
    await tester.pumpWidget(
      Column(
        children: [
          AppWindowScope(
            controller: window,
            geometry: window,
            child: Builder(
              builder: (context) {
                withoutKeys = AppWindowKeys.of(context);
                return const SizedBox();
              },
            ),
          ),
          Builder(
            builder: (context) {
              withoutScope = AppWindowKeys.of(context);
              return const SizedBox();
            },
          ),
        ],
      ),
    );

    expect(withoutKeys, same(AppWindowKeys.current));
    expect(withoutScope, same(AppWindowKeys.current));
  });

  test('updateShouldNotify מודיע כשהמפתחות מתחלפים', () {
    final keys = AppWindowKeys();
    final scope = AppWindowScope(
      controller: window,
      geometry: window,
      keys: keys,
      child: const SizedBox(),
    );

    expect(
      scope.updateShouldNotify(
        AppWindowScope(
          controller: window,
          geometry: window,
          keys: keys,
          child: const SizedBox(),
        ),
      ),
      isFalse,
    );
    expect(
      scope.updateShouldNotify(
        AppWindowScope(
          controller: window,
          geometry: window,
          keys: AppWindowKeys(),
          child: const SizedBox(),
        ),
      ),
      isTrue,
    );
  });

  group('activateWindow', () {
    const second = AppWindowId('window-2');
    tearDown(() {
      AppWindowKeys.resetForTest();
      LastActiveWindow.resetForTest();
    });

    test('החלון הראשי רשום כברירת מחדל', () {
      AppWindowKeys.activateWindow(AppWindowId.primary);
      expect(AppWindowKeys.current.id, AppWindowId.primary);
      expect(AppWindowKeys.current, same(original));
    });

    test('חלון רשום הופך לנוכחי ומסומן כפעיל אחרון', () {
      final keys = AppWindowKeys(id: second);
      AppWindowKeys.register(keys);

      AppWindowKeys.activateWindow(second);
      expect(AppWindowKeys.current, same(keys));
      expect(LastActiveWindow.id, second);

      AppWindowKeys.activateWindow(AppWindowId.primary);
      expect(AppWindowKeys.current, same(original));
      expect(LastActiveWindow.id, AppWindowId.primary);
    });

    test('מזהה לא רשום — מסומן בלבד, הנוכחי לא משתנה', () {
      AppWindowKeys.activateWindow(second);
      expect(LastActiveWindow.id, second);
      expect(AppWindowKeys.current, same(original));
    });

    test('ביטול רישום של הנוכחי חוזר לראשי; מופע זר לא מוחק רישום', () {
      final keys = AppWindowKeys(id: second);
      AppWindowKeys.register(keys);
      AppWindowKeys.activateWindow(second);

      AppWindowKeys.unregister(AppWindowKeys(id: second));
      expect(AppWindowKeys.current, same(keys));

      AppWindowKeys.unregister(keys);
      expect(AppWindowKeys.current, same(original));
      AppWindowKeys.activateWindow(second);
      expect(AppWindowKeys.current, same(original));
    });

    test('יעדי הסיור והמפתחות נגזרים מהחלון הפעיל', () {
      final keys = AppWindowKeys(id: second);
      AppWindowKeys.register(keys);
      AppWindowKeys.activateWindow(second);
      expect(AppWindowKeys.current.tour, same(keys.tour));
      expect(navigatorKey, same(keys.navigator));
    });
  });

  testWidgets('isActiveWindow: רק החלון הנוכחי; בלי scope — תמיד', (
    tester,
  ) async {
    final a = AppWindowKeys(id: const AppWindowId('a'));
    final b = AppWindowKeys(id: const AppWindowId('b'));
    late BuildContext inA;
    late BuildContext inB;
    late BuildContext outside;
    Widget scoped(AppWindowKeys keys, void Function(BuildContext) grab) =>
        AppWindowScope(
          controller: window,
          geometry: window,
          keys: keys,
          child: Builder(
            builder: (context) {
              grab(context);
              return const SizedBox();
            },
          ),
        );
    await tester.pumpWidget(
      Column(
        children: [
          scoped(a, (c) => inA = c),
          scoped(b, (c) => inB = c),
          Builder(
            builder: (context) {
              outside = context;
              return const SizedBox();
            },
          ),
        ],
      ),
    );

    AppWindowKeys.activate(a);
    expect(AppWindowKeys.isActiveWindow(inA), isTrue);
    expect(AppWindowKeys.isActiveWindow(inB), isFalse);
    expect(AppWindowKeys.isActiveWindow(outside), isTrue);
    AppWindowKeys.activate(b);
    expect(AppWindowKeys.isActiveWindow(inA), isFalse);
    expect(AppWindowKeys.isActiveWindow(inB), isTrue);
  });
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}
