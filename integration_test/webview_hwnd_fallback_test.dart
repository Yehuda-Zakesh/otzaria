// מצב HWND של WebView2 (#2736) נכפה דרך FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND
// כדי לבדוק על מחשב תקין. הרצה: flutter test <קובץ זה> -d windows
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart'
    show WindowsWebViewCreationFailures, WindowsWebViewHwndFallbacks;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

const String _forceHwndVariable = 'FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND';

// רקע מגנטה: פיקסל כזה על המסך יכול להגיע רק מהדף, לא מ-Flutter.
const String _probeHtml = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>hwnd-check</title>
<style>html, body { margin: 0; height: 100%; background: #ff00ff; }</style>
</head>
<body><div id="marker">webview-alive</div>
<script>window.probeValue = 41 + 1;</script>
</body>
</html>
''';
const int _magentaColorRef = 0x00FF00FF;

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

final _user32 = DynamicLibrary.open('user32.dll');
final _gdi32 = DynamicLibrary.open('gdi32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _findWindowEx = _user32
    .lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)
    >('FindWindowExW');
final _getWindowThreadProcessId = _user32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetWindowThreadProcessId');
final _isWindowVisible = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'IsWindowVisible',
    );
final _getWindowRect = _user32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_Rect>),
      int Function(int, Pointer<_Rect>)
    >('GetWindowRect');
final _setForegroundWindow = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'SetForegroundWindow',
    );
final _showWindow = _user32
    .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>(
      'ShowWindow',
    );
final _setWindowPos = _user32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
      int Function(int, int, int, int, int, int, int)
    >('SetWindowPos');
final _getDC = _user32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'GetDC',
    );
final _releaseDC = _user32
    .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
      'ReleaseDC',
    );
final _createCompatibleDC = _gdi32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
      'CreateCompatibleDC',
    );
final _createCompatibleBitmap = _gdi32
    .lookupFunction<
      IntPtr Function(IntPtr, Int32, Int32),
      int Function(int, int, int)
    >('CreateCompatibleBitmap');
final _selectObject = _gdi32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>(
      'SelectObject',
    );
final _deleteObject = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');
final _deleteDC = _gdi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
final _printWindow = _user32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Uint32),
      int Function(int, int, int)
    >('PrintWindow');
final _getPixel = _gdi32
    .lookupFunction<
      Uint32 Function(IntPtr, Int32, Int32),
      int Function(int, int, int)
    >('GetPixel');
final _setEnvironmentVariable = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)
    >('SetEnvironmentVariableW');

void _setForceHwnd(bool force) {
  final name = _forceHwndVariable.toNativeUtf16();
  final value = force ? '1'.toNativeUtf16() : nullptr;
  try {
    _setEnvironmentVariable(name, value);
  } finally {
    calloc.free(name);
    if (value != nullptr) calloc.free(value);
  }
}

int _findChild(int parent, String className, [int after = 0]) {
  final name = className.toNativeUtf16();
  try {
    return _findWindowEx(parent, after, name, nullptr);
  } finally {
    calloc.free(name);
  }
}

int _topWindow = 0;

/// חלון ה-FLUTTERVIEW של התהליך הזה (ייתכן שאוצריא אחרת פתוחה במחשב).
int _flutterView() {
  final processId = calloc<Uint32>();
  try {
    var top = 0;
    while ((top = _findChild(0, 'FLUTTER_RUNNER_WIN32_WINDOW', top)) != 0) {
      _getWindowThreadProcessId(top, processId);
      if (processId.value == pid) {
        // בלי main() של האפליקציה החלון נשאר מוסתר וקטן; מציגים אותו לבדיקה.
        if (_isWindowVisible(top) == 0) {
          _setWindowPos(top, 0, 40, 40, 1100, 800, 0x0004 /* SWP_NOZORDER */);
          _showWindow(top, 5 /* SW_SHOW */);
        }
        _setForegroundWindow(top);
        _topWindow = top;
        return _findChild(top, 'FLUTTERVIEW');
      }
    }
    return 0;
  } finally {
    calloc.free(processId);
  }
}

/// חלונות המארח של ה-WebView (CustomPlatformView) תחת FLUTTERVIEW.
List<int> _hostWindows() {
  final view = _flutterView();
  final windows = <int>[];
  var child = 0;
  while ((child = _findChild(view, 'CustomPlatformView', child)) != 0) {
    windows.add(child);
  }
  return windows;
}

List<int> _visibleHostWindows() =>
    _hostWindows().where((hwnd) => _isWindowVisible(hwnd) != 0).toList();

({int left, int top, int width, int height}) _windowRect(int hwnd) {
  final rect = calloc<_Rect>();
  try {
    _getWindowRect(hwnd, rect);
    final r = rect.ref;
    return (
      left: r.left,
      top: r.top,
      width: r.right - r.left,
      height: r.bottom - r.top,
    );
  } finally {
    calloc.free(rect);
  }
}

/// פיקסל של החלון העליון כפי ש-DWM מרכיב אותו, כולל חלונות ילד, גם כשחלון
/// אחר מסתיר אותו על המסך. [x], [y] בקואורדינטות מסך.
int _windowPixel(int x, int y) {
  final top = _topWindow;
  final frame = _windowRect(top);
  final screenDc = _getDC(0);
  final memoryDc = _createCompatibleDC(screenDc);
  final bitmap = _createCompatibleBitmap(screenDc, frame.width, frame.height);
  final previous = _selectObject(memoryDc, bitmap);
  try {
    _printWindow(top, memoryDc, 2 /* PW_RENDERFULLCONTENT */);
    return _getPixel(memoryDc, x - frame.left, y - frame.top) & 0x00FFFFFF;
  } finally {
    _selectObject(memoryDc, previous);
    _deleteObject(bitmap);
    _deleteDC(memoryDc);
    _releaseDC(0, screenDc);
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataDir;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('wv2_hwnd_check');
    AppPaths.debugOverrideDataRootPath(dataDir.path);
    await WebViewEnvironmentHolder.initialize();
  });

  tearDown(() async {
    _setForceHwnd(false);
    await WebViewEnvironmentHolder.disposeForAppRestart();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await dataDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('forced HWND mode renders, follows the layout and hides', (
    tester,
  ) async {
    _setForceHwnd(true);
    final events = <String>[];
    final webViewKey = UniqueKey();
    final fallbacks = <String>[];
    final fallbackSub = WindowsWebViewHwndFallbacks.stream.listen((fallback) {
      if (fallback.creationKey == webViewKey) fallbacks.add(fallback.stage);
    });
    final failureSub = WindowsWebViewCreationFailures.stream.listen((failure) {
      events.add('creation failed: ${failure.error}');
    });
    addTearDown(fallbackSub.cancel);
    addTearDown(failureSub.cancel);

    final controllerCompleter = Completer<InAppWebViewController>();
    final loaded = Completer<void>();
    final size = ValueNotifier(const Size(600, 400));
    final pages = PageController();
    addTearDown(size.dispose);
    addTearDown(pages.dispose);

    _flutterView();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: pages,
            children: [
              _KeepAlivePage(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder<Size>(
                    valueListenable: size,
                    builder: (context, value, child) =>
                        SizedBox.fromSize(size: value, child: child),
                    child: InAppWebView(
                      key: webViewKey,
                      webViewEnvironment: WebViewEnvironmentHolder.environment,
                      initialData: InAppWebViewInitialData(data: _probeHtml),
                      onWebViewCreated: controllerCompleter.complete,
                      onLoadStop: (controller, url) {
                        if (!loaded.isCompleted) loaded.complete();
                      },
                      onReceivedError: (controller, request, error) =>
                          events.add('navigation failed: ${error.description}'),
                    ),
                  ),
                ),
              ),
              const ColoredBox(color: Colors.white),
            ],
          ),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => loaded.isCompleted,
      timeout: const Duration(seconds: 30),
    );
    expect(loaded.isCompleted, isTrue, reason: 'events=$events');
    expect(fallbacks, ['forced']);

    final controller = await controllerCompleter.future;
    expect(
      await controller.evaluateJavascript(source: 'window.probeValue'),
      42,
    );
    expect(
      await controller.evaluateJavascript(
        source: "document.getElementById('marker').textContent",
      ),
      'webview-alive',
    );

    // הדף מצויר בחלון משלו, מעל Flutter, בגודל ה-widget.
    await _pumpUntil(tester, () => _visibleHostWindows().length == 1);
    expect(_visibleHostWindows(), hasLength(1));
    final host = _visibleHostWindows().single;
    final dpr = tester.view.devicePixelRatio;
    var rect = _windowRect(host);
    expect(rect.width, (600 * dpr).round());
    expect(rect.height, (400 * dpr).round());
    await _pumpFor(tester, const Duration(milliseconds: 500));
    final pixel = _windowPixel(
      rect.left + rect.width ~/ 2,
      rect.top + rect.height ~/ 2,
    );
    debugPrint('[HWND] center pixel: 0x${pixel.toRadixString(16)}');
    expect(pixel, _magentaColorRef, reason: 'תוכן הדף אינו על המסך');

    // שינוי גודל.
    size.value = const Size(500, 300);
    await _pumpUntil(
      tester,
      () => _windowRect(host).width == (500 * dpr).round(),
    );
    rect = _windowRect(host);
    expect(rect.width, (500 * dpr).round());
    expect(rect.height, (300 * dpr).round());

    // pause/resume — מה שהדיספצ'ר עושה במעבר טאב.
    await controller.pause();
    await _pumpUntil(tester, () => _visibleHostWindows().isEmpty);
    expect(_visibleHostWindows(), isEmpty, reason: 'pause לא הסתיר');
    await controller.resume();
    await _pumpUntil(tester, () => _visibleHostWindows().length == 1);
    expect(_visibleHostWindows(), hasLength(1), reason: 'resume לא הציג');

    // מעבר לעמוד אחר ב-PageView (כמו טאב שאינו פעיל).
    pages.jumpToPage(1);
    await _pumpUntil(tester, () => _visibleHostWindows().isEmpty);
    expect(_visibleHostWindows(), isEmpty, reason: 'עמוד לא פעיל נשאר גלוי');
    pages.jumpToPage(0);
    await _pumpUntil(tester, () => _visibleHostWindows().length == 1);
    expect(_visibleHostWindows(), hasLength(1));

    // דיאלוג של Flutter מעל התוסף.
    final context = tester.element(find.byType(PageView));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await _pumpUntil(tester, () => _visibleHostWindows().isEmpty);
    expect(_visibleHostWindows(), isEmpty, reason: 'דיאלוג מוסתר מתחת לתוסף');
    await _pumpFor(tester, const Duration(milliseconds: 300));
    rect = _windowRect(host);
    expect(
      _windowPixel(rect.left + 10, rect.top + 10),
      isNot(_magentaColorRef),
      reason: 'הדף עדיין מצויר מעל הדיאלוג',
    );
    Navigator.of(context).pop();
    await _pumpUntil(tester, () => _visibleHostWindows().length == 1);
    expect(_visibleHostWindows(), hasLength(1));

    // dispose הורס את החלון.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => _hostWindows().isEmpty);
    expect(_hostWindows(), isEmpty, reason: 'חלון המארח לא נהרס');
  }, skip: !Platform.isWindows);

  testWidgets('composition mode stays the default', (tester) async {
    final webViewKey = UniqueKey();
    final fallbacks = <String>[];
    final fallbackSub = WindowsWebViewHwndFallbacks.stream.listen((fallback) {
      fallbacks.add(fallback.stage);
    });
    addTearDown(fallbackSub.cancel);
    final loaded = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InAppWebView(
            key: webViewKey,
            webViewEnvironment: WebViewEnvironmentHolder.environment,
            initialData: InAppWebViewInitialData(data: _probeHtml),
            onLoadStop: (controller, url) {
              if (!loaded.isCompleted) loaded.complete();
            },
          ),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => loaded.isCompleted,
      timeout: const Duration(seconds: 30),
    );
    expect(loaded.isCompleted, isTrue);
    expect(fallbacks, isEmpty);
    expect(find.byType(Texture), findsOneWidget);
    expect(_visibleHostWindows(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isWindows);
}
