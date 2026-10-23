import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';

/// שני חלונות באותו isolate לא חולקים צמתי פוקוס, טקסט איתור ומחסנית שחזור.
void main() {
  tearDown(AppWindowKeys.resetForTest);

  testWidgets(
    'דיאלוג נשאר במאגר החלון שלו בעת יצירה וסגירה כשהפוקוס בחלון אחר',
    (tester) async {
      final a = AppWindowKeys(id: const AppWindowId('probe-a'));
      final b = AppWindowKeys(id: const AppWindowId('probe-b'));
      final repoA = FocusRepository.forWindow(a);
      final repoB = FocusRepository.forWindow(b);
      addTearDown(() {
        repoA.resetForTesting();
        repoB.resetForTesting();
        AppWindowKeys.resetForTest();
      });
      AppWindowKeys.register(a);
      AppWindowKeys.register(b);
      AppWindowKeys.activateWindow(b.id);
      var screenRestores = 0;
      repoA.setScreenRestorer(
        restore: () => screenRestores++,
        canRestore: () => true,
      );
      final window = _FakeWindow();
      await tester.pumpWidget(
        AppWindowScope(
          controller: window,
          geometry: window,
          keys: a,
          child: const MaterialApp(home: _DialogProbe()),
        ),
      );
      repoA.restoreNowForTesting();
      expect(
        screenRestores,
        0,
        reason:
            'The mounted dialog must receive restore instead of its underlying screen',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repoA.restoreNowForTesting();
      expect(screenRestores, 1);
    },
  );

  test('FocusRepository() הוא המופע של החלון הנוכחי, ויציב', () {
    expect(FocusRepository(), same(FocusRepository.current));
    expect(FocusRepository(), same(FocusRepository()));
    expect(
      FocusRepository.current,
      same(FocusRepository.forWindow(AppWindowKeys.current)),
    );
  });

  test('לכל חלון מופע נפרד ועצמאי', () {
    final a = AppWindowKeys();
    final b = AppWindowKeys(id: const AppWindowId('window-2'));
    final repoA = FocusRepository.forWindow(a);
    final repoB = FocusRepository.forWindow(b);
    expect(repoA, isNot(same(repoB)));
    expect(FocusRepository.forWindow(a), same(repoA));

    repoA.findRefSearchController.text = 'בראשית';
    expect(repoB.findRefSearchController.text, isEmpty);
    expect(
      repoA.findRefSearchFocusNode,
      isNot(same(repoB.findRefSearchFocusNode)),
    );

    var restoredA = 0, restoredB = 0;
    repoA.setScreenRestorer(restore: () => restoredA++, canRestore: () => true);
    repoB.setScreenRestorer(restore: () => restoredB++, canRestore: () => true);
    repoA.restoreNowForTesting();
    expect(restoredA, 1);
    expect(restoredB, 0);
  });

  test('current עוקב אחרי activateWindow', () {
    const id = AppWindowId('window-2');
    final keys = AppWindowKeys(id: id);
    AppWindowKeys.register(keys);
    final primary = FocusRepository();

    AppWindowKeys.activateWindow(id);
    expect(FocusRepository(), same(FocusRepository.forWindow(keys)));
    expect(FocusRepository(), isNot(same(primary)));

    AppWindowKeys.activateWindow(AppWindowId.primary);
    expect(FocusRepository(), same(primary));
  });

  testWidgets('of(context) — לפי ה-scope, ובלי scope — הנוכחי', (
    tester,
  ) async {
    final window = _FakeWindow();
    final a = AppWindowKeys();
    final b = AppWindowKeys(id: const AppWindowId('window-2'));
    late FocusRepository inA, inB, outside;
    Widget probe(void Function(FocusRepository) sink) => Builder(
      builder: (context) {
        sink(FocusRepository.of(context));
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      Column(
        children: [
          AppWindowScope(
            controller: window,
            geometry: window,
            keys: a,
            child: probe((r) => inA = r),
          ),
          AppWindowScope(
            controller: window,
            geometry: window,
            keys: b,
            child: probe((r) => inB = r),
          ),
          probe((r) => outside = r),
        ],
      ),
    );

    expect(inA, same(FocusRepository.forWindow(a)));
    expect(inB, same(FocusRepository.forWindow(b)));
    expect(inA, isNot(same(inB)));
    expect(outside, same(FocusRepository()));
  });
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}

class _DialogProbe extends StatefulWidget {
  const _DialogProbe();
  @override
  State<_DialogProbe> createState() => _DialogProbeState();
}

class _DialogProbeState extends State<_DialogProbe>
    with DialogFocusRestorerMixin<_DialogProbe> {
  final node = FocusNode();
  @override
  void initState() {
    super.initState();
    registerDialogFocusRestorer(node);
  }

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: node, child: const SizedBox());
}
