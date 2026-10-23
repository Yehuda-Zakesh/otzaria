import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/plugins/services/plugin_webview_diagnostics.dart';

void main() {
  test('reads kind, pid and the main frame of each process', () {
    final processes = pluginWebViewProcesses([
      BrowserProcessInfo(kind: BrowserProcessKind.BROWSER, processId: 1),
      BrowserProcessInfo(
        kind: BrowserProcessKind.RENDERER,
        processId: 2,
        frameInfos: [
          FrameInfo(
            isMainFrame: true,
            request: URLRequest(
              url: WebUri.uri(
                Uri.file(r'C:\p\my.plugin\index.html', windows: true),
              ),
            ),
          ),
        ],
      ),
      BrowserProcessInfo(kind: BrowserProcessKind.GPU),
    ]);

    expect(processes, [
      (kind: 'BROWSER', pid: 1, page: null),
      (kind: 'RENDERER', pid: 2, page: 'my.plugin/index.html'),
    ]);
  });

  group('framePageLabel', () {
    test('a file page keeps only its folder and file name', () {
      expect(
        framePageLabel(
          Uri.file(
            r'C:\Users\someone\plugins\my.plugin\index.html',
            windows: true,
          ),
        ),
        'my.plugin/index.html',
      );
    });

    test('other schemes keep only the host', () {
      expect(
        framePageLabel(Uri.parse('otzaria-plugin://my.plugin/a/b.html')),
        'my.plugin',
      );
      expect(framePageLabel(Uri.parse('http://localhost:5173/')), 'localhost');
      expect(framePageLabel(null), isNull);
    });
  });

  test('registration fills the diagnostics lister once', () {
    final diagnostics = DeveloperDiagnostics.instance..resetForTesting();
    addTearDown(diagnostics.resetForTesting);
    expect(diagnostics.webViewProcessLister, isNull);
    registerPluginWebViewDiagnostics();
    final lister = diagnostics.webViewProcessLister;
    expect(lister, isNotNull);
    registerPluginWebViewDiagnostics();
    expect(identical(diagnostics.webViewProcessLister, lister), isTrue);
  });
}
