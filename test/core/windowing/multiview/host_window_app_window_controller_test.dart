import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/multiview/host_window_app_window_controller.dart';
import 'package:window_manager/window_manager.dart' show ResizeEdge;

import '../../../test_helpers/fake_view_window.dart';
import '../../../test_helpers/second_test_view.dart';

void main() {
  testWidgets('גבולות לוגיים לפי ה-DPR של התצוגה, ופעולות על החלון הזה', (
    tester,
  ) async {
    final view = SecondTestView(tester.view)..devicePixelRatio = 1.5;
    final stub = StubWindowController(view);
    final handle = StubWindowHandle(stub, (_) {}, fakeHwnd: 7);
    final native = FakeViewWindowNative()
      ..rects[7] = const Rect.fromLTWH(300, 150, 1200, 900)
      ..area = const Rect.fromLTWH(0, 0, 3000, 2000);
    var closes = 0;
    final window = HostWindowAppWindowController(
      id: const AppWindowId('window-view-2'),
      handle: handle,
      onClose: () async => closes++,
      native: native,
    );

    expect(await window.getBounds(), const Rect.fromLTWH(200, 100, 800, 600));
    await window.setBounds(const Rect.fromLTWH(10, 20, 400, 300));
    expect(native.rects[7], const Rect.fromLTWH(15, 30, 600, 450));
    await window.setSize(const Size(800, 600));
    expect(native.rects[7], const Rect.fromLTWH(15, 30, 1200, 900));
    await window.center();
    expect(native.rects[7]!.center, const Offset(1500, 1000));

    await window.maximize();
    expect(await window.isMaximized(), isTrue);
    await window.unmaximize();
    expect(await window.isMaximized(), isFalse);
    await window.minimize();
    expect(await window.isMinimized(), isTrue);
    // focus אינו SW_RESTORE על חלון גלוי: רק חלון ממוזער חוזר.
    await window.focus();
    expect(await window.isMinimized(), isFalse);
    expect(native.focused, [7]);
    await window.startDragging();
    expect(native.dragged, [7]);
    await window.startResizing(ResizeEdge.topLeft);
    expect(native.resized, [(7, ResizeEdge.topLeft)]);
    await window.maximizeVertically();
    expect(native.maximizedVertically, [7]);
    await window.setMinimumSize(const Size(420, 400));
    expect(
      stub.constraints,
      const BoxConstraints(minWidth: 420, minHeight: 400),
    );
    expect(await window.isVisible(), isTrue);
    expect(window.stateChanges, same(handle.changes));

    await window.close();
    expect(closes, 1);
    expect(window.quitApplication, throwsUnsupportedError);

    // אחרי ההריסה אין HWND, והשאילתות אינן זורקות.
    handle.markDestroyed();
    await window.startResizing(ResizeEdge.top);
    expect(native.resized, hasLength(1));
    expect(await window.isVisible(), isFalse);
    expect(await window.getBounds(), Rect.zero);
    expect(await window.isMaximized(), isFalse);
  });
}
