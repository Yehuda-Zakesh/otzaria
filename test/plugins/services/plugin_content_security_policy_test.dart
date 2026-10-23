import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:path/path.dart' as p;

/// מקורות ההוראה [directive] מתוך ה-CSP.
List<String> _sources(String csp, String directive) => csp
    .split(';')
    .map((part) => part.trim().split(' '))
    .firstWhere((tokens) => tokens.first == directive)
    .skip(1)
    .toList();

void main() {
  group('buildPluginContentSecurityPolicy', () {
    final csp = buildPluginContentSecurityPolicy(
      pluginId: 'test.plugin',
      fileServerPort: 53111,
      policy: const PluginNetworkPolicy(
        prefixes: [
          'https://github.com/Otzaria/otzaria-library',
          'https://api.example.com',
          'https://api.example.com/v1?key=1',
        ],
        loopbackHosts: ['127.0.0.1'],
      ),
    );

    test('default-src ו-form-action מוגבלים לאותם יעדים', () {
      final destinations = _sources(
        csp,
        'default-src',
      ).where((s) => !s.startsWith("'unsafe") && s != "'wasm-unsafe-eval'");
      expect(destinations, _sources(csp, 'form-action'));
    });

    test('קידומת עם נתיב: הנתיב עצמו ומה שתחתיו', () {
      final sources = _sources(csp, 'default-src');
      expect(sources, contains('https://github.com/Otzaria/otzaria-library'));
      expect(sources, contains('https://github.com/Otzaria/otzaria-library/'));
      expect(sources, contains('https://api.example.com'));
      expect(sources, contains('https://api.example.com/v1/'));
      expect(sources.where((s) => s.contains('?')), isEmpty);
    });

    test('WebSocket ליעד מותר', () {
      final sources = _sources(csp, 'default-src');
      expect(sources, contains('wss://api.example.com'));
      expect(sources, contains('wss://github.com/Otzaria/otzaria-library/'));
      expect(sources, contains('ws://127.0.0.1:*'));
    });

    test('שרת הקבצים רק בפורט שלו ובנתיבי התוסף עצמו', () {
      final sources = _sources(csp, 'default-src');
      expect(sources, contains('http://127.0.0.1:53111/f/test.plugin/'));
      expect(sources, contains('http://127.0.0.1:53111/w/'));
      expect(sources, contains('http://127.0.0.1:53111/fonts/'));
      expect(sources, contains('http://localhost:53111/fonts/'));
      expect(sources.where((s) => s.contains(':*/')), isEmpty);
    });

    test('loopback וקבצי התוסף', () {
      final sources = _sources(csp, 'default-src');
      expect(sources, contains('http://127.0.0.1:*'));
      expect(sources, contains('$pluginAssetScheme://test.plugin'));
      expect(sources.where((s) => s.contains('githubusercontent')), isEmpty);
    });

    test('בלי מדיניות רשת אין שום מקור http(s) חיצוני', () {
      final closed = buildPluginContentSecurityPolicy(
        pluginId: 'test.plugin',
        policy: PluginNetworkPolicy.none,
        fileServerPort: 53111,
      );
      final external = _sources(closed, 'default-src').where(
        (s) =>
            (s.startsWith('http') || s.startsWith('ws')) &&
            !s.startsWith('http://127.0.0.1:53111/') &&
            !s.startsWith('http://localhost:53111/'),
      );
      expect(external, isEmpty);
    });
  });

  group('servePluginAsset', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('plugin_csp_test');
      await File(p.join(root.path, 'index.html')).writeAsString('<p>x</p>');
    });

    tearDown(() => root.delete(recursive: true));

    test('מצרף את ה-CSP לתשובה', () async {
      final response = await servePluginAsset(
        url: WebUri('$pluginAssetScheme://test.plugin/index.html'),
        pluginId: 'test.plugin',
        rootPath: root.path,
        contentSecurityPolicy: "default-src 'self'",
      );

      expect(response!.headers, {
        pluginContentSecurityPolicyHeader: "default-src 'self'",
      });
    });
  });
}
