import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';

class _RecordingController extends Fake implements InAppWebViewController {
  final calls = <String>[];

  @override
  Future<dynamic> callDevToolsProtocolMethod({
    required String methodName,
    Map<String, dynamic>? parameters,
  }) async {
    calls.add('$methodName $parameters');
    if (calls.length == 1) throw Exception('CDP לא זמין');
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    calls.add('load ${urlRequest.url}');
  }
}

class _NoopBridge extends Fake implements PluginBridgeHandler {
  @override
  void register(InAppWebViewController controller) {}
}

class _Host extends State<StatefulWidget> with PluginWebViewHost {
  @override
  final plugin = InstalledPlugin(
    pluginId: 'dev.plugin',
    name: 'Dev',
    version: '1.0.0',
    installPath: '/',
    entrypointPath: 'http://localhost:3000',
    enabled: true,
    pinned: false,
    sourceType: 'localhost_dev',
    devRootPath: 'http://localhost:3000',
    manifest: PluginManifest(
      schemaVersion: 1,
      id: 'dev.plugin',
      name: 'Dev',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '1.0.0',
      sdkVersion: '1.x',
      permissions: const [],
      networkEnabled: false,
      networkAllowlist: const [],
      toolTabTitle: 'Dev',
      toolTabOrder: 1,
      defaultPinned: false,
      publishedDataTypes: const [],
    ),
    installedAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  String get instanceId => 'test';

  @override
  String get logTag => 'Plugin';

  @override
  BuildContext? get dialogContext => null;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  test('תוסף פיתוח נטען מהשרת שלו כשה-WebView מתחבר', () async {
    final host = _Host()..bridge = _NoopBridge();
    final controller = _RecordingController();
    addTearDown(
      () => PluginRuntimeDispatcher.instance.unregisterController(
        'dev.plugin',
        instanceId: 'test',
      ),
    );

    expect(
      host.attachPluginController(
        controller,
        WebUri('http://localhost:3000'),
      ),
      isTrue,
    );
    await pumpEventQueue();

    expect(controller.calls.last, 'load http://localhost:3000');
  });

  test(
    'שרת פיתוח נטען רק אחרי עקיפת המטמון וה-service worker (issue #2060)',
    () async {
      final controller = _RecordingController();

      await loadPluginDevServer(controller, WebUri('http://localhost:3000'));

      expect(controller.calls.last, 'load http://localhost:3000');
      if (Platform.isWindows) {
        expect(controller.calls, [
          'Network.setCacheDisabled {cacheDisabled: true}',
          'Network.setBypassServiceWorker {bypass: true}',
          'load http://localhost:3000',
        ]);
      }
    },
  );
}
