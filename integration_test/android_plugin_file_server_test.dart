// תוסף ב-Android טוען קבצי משתמש משרת הקבצים ב-HTTP גלוי ל-127.0.0.1.
// הרצה: flutter test integration_test/android_plugin_file_server_test.dart -d <android>
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WebView fetches a registered file from the plugin file server',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('plugin_file_server');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/note.txt')
        ..writeAsStringSync('שלום מהשרת');
      final registration = await PluginFileServer.instance.register(
        pluginId: 'com.example.probe',
        canonicalPath: file.path,
      );

      final loaded = Completer<InAppWebViewController>();
      final console = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: '<!DOCTYPE html><html><body>probe</body></html>',
              ),
              onConsoleMessage: (controller, message) =>
                  console.add(message.message),
              onLoadStop: (controller, url) {
                if (!loaded.isCompleted) loaded.complete(controller);
              },
            ),
          ),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!loaded.isCompleted && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(loaded.isCompleted, isTrue, reason: 'הדף לא נטען');

      final result = await (await loaded.future).callAsyncJavaScript(
        functionBody:
            'try { const r = await fetch(url); return await r.text(); }'
            ' catch (e) { return "error: " + e; }',
        arguments: {'url': registration.url},
      );
      expect(
        result?.value,
        'שלום מהשרת',
        reason: 'url=${registration.url} console=$console',
      );
    },
    skip: !Platform.isAndroid,
  );
}
