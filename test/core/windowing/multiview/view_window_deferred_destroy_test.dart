import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';

import '../../../test_helpers/fake_view_window.dart';

/// Linux: הריסת חלון עם פריים בדרך קורסת, ולכן הסדר הוא הסתרה, פירוק העץ,
/// כמה פריימים, ורק אז הריסה.
void main() {
  tearDown(() {
    AppWindowKeys.resetForTest();
  });

  Future<FakeViewWindows> pumpHost(
    WidgetTester tester, {
    required bool defersDestroy,
  }) async {
    final windows = FakeViewWindows(tester)..defersDestroy = defersDestroy;
    await tester.pumpWidget(
      MultiViewHost(
        registry: windows.registry,
        contentBuilder: (context, entry) => const SizedBox.shrink(),
        child: const SizedBox.shrink(),
      ),
    );
    return windows;
  }

  testWidgets('נדחית: מוסתר ומפורק מיד, נהרס ומשוחרר רק אחרי פריימים', (
    tester,
  ) async {
    final windows = await pumpHost(tester, defersDestroy: true);
    final entry = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    await entry.firstFrame;
    final hwnd = entry.handle.nativeHandle!;
    final stub = windows.stubOf(entry);
    expect(find.byType(View), findsNWidgets(2));

    entry.handle.destroy();
    entry.handle.destroy();

    expect(windows.native.hidden, [hwnd]);
    expect(windows.registry.windows, isEmpty);
    expect(AppWindowKeys.byId(entry.id), isNull);
    expect(stub.destroyed, isFalse);

    await tester.pump();
    expect(find.byType(View), findsOneWidget, reason: 'התצוגה פורקה');
    expect(stub.destroyed, isFalse, reason: 'עוד לא עברו מספיק פריימים');

    await tester.pump();
    await tester.pump();
    expect(stub.destroyed, isTrue);
    expect(stub.disposed, isFalse, reason: 'השחרור אחרי הפריים הבא');

    await tester.pump();
    expect(stub.disposed, isTrue);
    expect(windows.native.hidden, [hwnd], reason: 'הסתרה אחת בלבד');
  });

  testWidgets('כשאין פריימים, ההריסה אינה נתקעת', (tester) async {
    final windows = await pumpHost(tester, defersDestroy: true);
    final entry = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    final stub = windows.stubOf(entry);

    entry.handle.destroy();
    // בלי pump אין פריים; כל המתנה מוגבלת בזמן.
    await tester.binding.delayed(const Duration(milliseconds: 1600));
    expect(stub.destroyed, isTrue);
    await tester.pump();
  });

  testWidgets('לא נדחית (Windows): הריסה מיידית ובלי הסתרה', (tester) async {
    final windows = await pumpHost(tester, defersDestroy: false);
    final entry = windows.registry.open(size: const Size(800, 600))!;
    await tester.pump();
    final stub = windows.stubOf(entry);

    entry.handle.destroy();

    expect(stub.destroyed, isTrue);
    expect(windows.native.hidden, isEmpty);
    expect(windows.registry.windows, isEmpty);
    await tester.pump();
    expect(stub.disposed, isTrue);
  });
}
