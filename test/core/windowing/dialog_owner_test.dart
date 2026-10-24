import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:windows_file_picker/windows_file_picker.dart';

import '../../test_helpers/fake_view_window.dart';

/// G5: דיאלוג מערכת שנפתח מחלון Dart צריך את ה-HWND של אותו חלון כבעלים,
/// ולא את החלון הראשי (שעשוי להיות מוסתר).
void main() {
  const mainHwnd = 7;

  setUp(() {
    DialogOwner.mainWindowHwnd = mainHwnd;
  });

  tearDown(() {
    DialogOwner.resetForTest();
    AppWindowKeys.resetForTest();
    LastActiveWindow.resetForTest();
  });

  testWidgets('בלי חלון Dart פעיל — החלון הראשי', (tester) async {
    final windows = FakeViewWindows(tester);
    windows.registry.open(size: const Size(800, 600));
    expect(AppWindowKeys.current.id, AppWindowId.primary);
    expect(DialogOwner.hwnd(registry: windows.registry), mainHwnd);
  });

  testWidgets('חלון Dart פעיל — ה-HWND שלו', (tester) async {
    final windows = FakeViewWindows(tester);
    windows.registry.open(size: const Size(800, 600));
    final b = windows.registry.open(size: const Size(800, 600))!;
    AppWindowKeys.activateWindow(b.id);
    expect(
      DialogOwner.hwnd(registry: windows.registry),
      windows.handleOf(b).fakeHwnd,
    );
  });

  testWidgets('עם context — החלון שלו, גם כשחלון אחר פעיל', (tester) async {
    final windows = FakeViewWindows(tester);
    final a = windows.registry.open(size: const Size(800, 600))!;
    final b = windows.registry.open(size: const Size(800, 600))!;
    AppWindowKeys.activateWindow(b.id);
    late BuildContext inA;
    await tester.pumpWidget(
      AppWindowScope(
        controller: a.controller,
        geometry: a.controller,
        keys: a.keys,
        child: Builder(
          builder: (context) {
            inA = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(
      DialogOwner.hwnd(context: inA, registry: windows.registry),
      windows.handleOf(a).fakeHwnd,
    );
  });

  testWidgets('מקור מפורש שסוגר או נהרס אינו נופל לראשי', (tester) async {
    final windows = FakeViewWindows(tester);
    final a = windows.registry.open(size: const Size(800, 600))!;
    late BuildContext inA;
    await tester.pumpWidget(
      AppWindowScope(
        controller: a.controller,
        geometry: a.controller,
        keys: a.keys,
        child: Builder(
          builder: (context) {
            inA = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    a.closing = true;
    expect(DialogOwner.hwnd(context: inA, registry: windows.registry), isNull);
    a.handle.destroy();
    expect(DialogOwner.hwnd(context: inA, registry: windows.registry), isNull);
  });

  testWidgets('חלון שנהרס — חוזר לראשי', (tester) async {
    final windows = FakeViewWindows(tester);
    final a = windows.registry.open(size: const Size(800, 600))!;
    AppWindowKeys.activateWindow(a.id);
    a.handle.destroy();
    expect(DialogOwner.hwnd(registry: windows.registry), mainHwnd);
  });

  test('ראשי מוסתר אינו בעלים: הפלאגין נופל לחלון שבחזית', () {
    expect(DialogOwner.hwnd(isMainShown: false), isNull);
    expect(DialogOwner.hwnd(isMainShown: true), mainHwnd);
  });

  test('אפשרויות בורר הקבצים: מודאלי, עם הבעלים המפורש', () {
    final options = modalWindowsOptions();
    expect(options, isA<FilePickerWindowsOptions>());
    options as FilePickerWindowsOptions;
    expect(options.lockParentWindow, isTrue);
    expect(options.parentWindowHandle, mainHwnd);
  });
}
