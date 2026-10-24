import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview_linux/flutter_inappwebview_linux.dart'
    show LinuxWebViewHostWindow;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/linux_webview_host.dart';

import '../../../test_helpers/fake_view_window.dart';

void main() {
  tearDown(() {
    LinuxWebViewHostWindow.resolver = null;
    AppWindowKeys.resetForTest();
  });

  testWidgets('מחזיר את החלון וה-FlView של התצוגה לפי viewId', (tester) async {
    final windows = FakeViewWindows(tester);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    installLinuxWebViewHostResolver(windows.registry);
    final resolve = LinuxWebViewHostWindow.resolver!;

    final hwndA = windows.handleOf(a).fakeHwnd!;
    final hwndB = windows.handleOf(b).fakeHwnd!;
    expect(resolve(a.handle.view.viewId), (
      windowHandle: hwndA,
      flutterViewHandle: hwndA + 1000,
    ));
    expect(resolve(b.handle.view.viewId), (
      windowHandle: hwndB,
      flutterViewHandle: hwndB + 1000,
    ));
  });

  testWidgets('null לתצוגה הראשית ולמזהה לא מוכר', (tester) async {
    final windows = FakeViewWindows(tester);
    windows.registry.open(size: const Size(800, 600));
    installLinuxWebViewHostResolver(windows.registry);
    final resolve = LinuxWebViewHostWindow.resolver!;

    expect(tester.view.viewId, 0);
    expect(resolve(0), isNull);
    expect(resolve(999), isNull);
  });

  testWidgets('חלון שנסגר אינו מארח עוד', (tester) async {
    final windows = FakeViewWindows(tester);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final viewId = a.handle.view.viewId;
    installLinuxWebViewHostResolver(windows.registry);

    a.handle.destroy();
    await tester.pump();

    expect(LinuxWebViewHostWindow.resolver!(viewId), isNull);
  });

  testWidgets('Linux: חלון בהריסה נדחית אינו מארח לפני שנהרס בפועל', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester)..defersDestroy = true;
    final a = windows.registry.open(size: const Size(800, 600))!;
    final viewId = a.handle.view.viewId;
    installLinuxWebViewHostResolver(windows.registry);

    a.handle.destroy();

    expect(windows.stubOf(a).destroyed, isFalse);
    expect(LinuxWebViewHostWindow.resolver!(viewId), isNull);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(windows.stubOf(a).destroyed, isTrue);
  });
}
