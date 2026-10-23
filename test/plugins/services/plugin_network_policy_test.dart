import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';

PluginManifest _manifest(List<String> allowlist, {bool enabled = true}) =>
    PluginManifest(
      schemaVersion: 1,
      id: 'test.plugin',
      name: 'Test Plugin',
      version: '1.0.0',
      description: '',
      author: '',
      homepage: '',
      entrypoint: 'index.html',
      minAppVersion: '0.0.0',
      sdkVersion: '1.x',
      permissions: const ['network.access', 'network.localhost'],
      networkEnabled: enabled,
      networkAllowlist: allowlist,
      toolTabTitle: 'Test Plugin',
      toolTabOrder: 1,
      defaultPinned: true,
      publishedDataTypes: const [],
    );

class _FakeRegistry implements PluginRegistryRepository {
  _FakeRegistry(this.grants);

  final Map<String, bool> grants;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      grants[permission];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<PluginNetworkAccessResolver> _resolverWithOfficial(String body) async {
  final resolver = PluginNetworkAccessResolver(
    client: MockClient(
      (_) async => http.Response(
        body,
        200,
        headers: const {'content-type': 'text/plain; charset=utf-8'},
      ),
    ),
  );
  await resolver.loadOfficialAllowlist();
  return resolver;
}

Future<PluginNetworkPolicy> _policy(
  List<String> allowlist, {
  Map<String, bool> grants = const {
    'network.access': true,
    'network.localhost': true,
  },
  String official = 'https://github.com/Otzaria\nhttps://api.example.com/v1\n',
}) async => resolvePluginNetworkPolicy(
  pluginId: 'test.plugin',
  manifest: _manifest(allowlist),
  registry: _FakeRegistry(grants),
  resolver: await _resolverWithOfficial(official),
);

/// מדמה את WebKit: הכלל האחרון שתואם קובע, וכל החריגה באה אחרי חסימת הכל.
bool _allowed(List<ContentBlocker> rules, String url) {
  var blocked = false;
  for (final rule in rules) {
    final trigger = rule.trigger;
    final pattern = RegExp(
      trigger.urlFilter,
      caseSensitive: trigger.urlFilterIsCaseSensitive,
    );
    if (!pattern.hasMatch(url)) continue;
    blocked = rule.action.type == ContentBlockerActionType.BLOCK;
  }
  return !blocked;
}

void main() {
  group('resolvePluginNetworkPolicy', () {
    test('מתיר רק מה שמכוסה גם במניפסט וגם ברשימה הרשמית', () async {
      final policy = await _policy([
        'https://github.com/Otzaria/otzaria-library',
        'https://api.example.com',
        'https://evil.example.org',
      ]);

      expect(
        policy.prefixes,
        unorderedEquals([
          'https://github.com/Otzaria/otzaria-library',
          'https://api.example.com/v1',
        ]),
      );
    });

    test('בלי הרשאת network.access אין יעד מרוחק', () async {
      final policy = await _policy(
        [
          'https://github.com/Otzaria/otzaria-library',
          'http://127.0.0.1:11434',
        ],
        grants: const {'network.localhost': true},
      );

      expect(policy.prefixes, ['http://127.0.0.1:11434']);
    });

    test('loopback דורש network.localhost', () async {
      final policy = await _policy(
        ['127.0.0.1', 'http://localhost:1234'],
        grants: const {'network.access': true},
      );

      expect(policy.prefixes, isEmpty);
      expect(policy.loopbackHosts, isEmpty);
    });

    test('מניפסט בלי network.enabled אינו מתיר דבר', () async {
      final policy = await resolvePluginNetworkPolicy(
        pluginId: 'test.plugin',
        manifest: _manifest([
          'https://github.com/Otzaria/otzaria-library',
        ], enabled: false),
        registry: _FakeRegistry(const {'network.access': true}),
        resolver: await _resolverWithOfficial('https://github.com/Otzaria\n'),
      );

      expect(policy.prefixes, isEmpty);
    });

    test('טעינת הרשימה הרשמית אחרי כשל מודיעה על שינוי במדיניות', () async {
      var online = false;
      var now = DateTime(2026);
      final resolver = PluginNetworkAccessResolver(
        client: MockClient(
          (_) async => online
              ? http.Response(
                  'https://api.example.com\n',
                  200,
                  headers: const {'content-type': 'text/plain'},
                )
              : http.Response('', 503),
        ),
        nowProvider: () => now,
      );
      expect(await resolver.loadOfficialAllowlist(), isNull);

      final changed = PluginNetworkPolicy.changes.first;
      online = true;
      now = now.add(const Duration(hours: 1));
      await resolver.loadOfficialAllowlist();

      await expectLater(changed, completion(isNull));
    });
  });

  group('buildPluginContentBlockers', () {
    late List<ContentBlocker> rules;

    setUpAll(() async {
      rules = buildPluginContentBlockers(
        pluginId: 'test.plugin',
        fileServerPort: 53111,
        policy: await _policy([
          'https://github.com/Otzaria/otzaria-library',
          '127.0.0.1',
        ]),
      );
    });

    test('הכלל הראשון חוסם הכל', () {
      expect(rules.first.trigger.urlFilter, '.*');
      expect(rules.first.action.type, ContentBlockerActionType.BLOCK);
    });

    test('קידומת מותרת: נתיבים תחתיה מותרים, קידומת דומה לא', () {
      const base = 'https://github.com/Otzaria/otzaria-library';
      expect(_allowed(rules, '$base/releases/latest'), isTrue);
      expect(_allowed(rules, '$base?tab=readme'), isTrue);
      expect(
        _allowed(rules, 'wss://github.com/Otzaria/otzaria-library/ws'),
        isTrue,
      );
      expect(_allowed(rules, '${base}2/x'), isFalse);
      expect(_allowed(rules, 'https://github.com/'), isFalse);
    });

    test('יעד שאינו ברשימה נחסם, כולל WebSocket', () {
      expect(_allowed(rules, 'https://evil.example.org/collect?d=1'), isFalse);
      expect(_allowed(rules, 'wss://evil.example.org/'), isFalse);
      expect(_allowed(rules, 'http://192.168.1.10/'), isFalse);
    });

    test('ה-CDN של GitHub Releases אינו נפתח בגלל יעד ב-github.com', () {
      expect(
        _allowed(rules, 'https://objects.githubusercontent.com/x'),
        isFalse,
      );
      expect(
        _allowed(rules, 'https://release-assets.githubusercontent.com/x'),
        isFalse,
      );
    });

    test('שרת הקבצים: רק הנתיבים של התוסף עצמו, גם כש-loopback מוצהר', () {
      expect(
        _allowed(rules, 'http://127.0.0.1:53111/f/test.plugin/abc'),
        isTrue,
      );
      expect(_allowed(rules, 'http://127.0.0.1:53111/w/token'), isTrue);
      expect(
        _allowed(rules, 'http://127.0.0.1:53111/fonts/token/b-x.ttf'),
        isTrue,
      );
      expect(
        _allowed(rules, 'http://127.0.0.1:53111/f/other.plugin/abc'),
        isFalse,
      );
      expect(
        _allowed(rules, 'http://localhost:53111/f/other.plugin/abc'),
        isFalse,
      );
      expect(_allowed(rules, 'http://127.0.0.1:53111/'), isFalse);
    });

    test('נתיבי שרת הקבצים אינם פותחים שרת מקומי אחר', () {
      final closed = buildPluginContentBlockers(
        pluginId: 'test.plugin',
        policy: PluginNetworkPolicy.none,
        fileServerPort: 53111,
      );

      expect(_allowed(closed, 'http://127.0.0.1:53111/w/token'), isTrue);
      expect(_allowed(closed, 'http://127.0.0.1:8080/w/exfil?d=1'), isFalse);
      expect(
        _allowed(closed, 'http://localhost:8080/f/test.plugin/x'),
        isFalse,
      );
    });

    test('host של loopback בלי פורט מתיר כל פורט', () {
      expect(_allowed(rules, 'http://127.0.0.1:11434/api/chat'), isTrue);
      expect(_allowed(rules, 'http://localhost:11434/api/chat'), isFalse);
    });

    test('דף התוסף עצמו ותוכן מקומי מותרים', () {
      expect(_allowed(rules, 'data:image/png;base64,AAAA'), isTrue);
      expect(_allowed(rules, 'blob:null/1234'), isTrue);
      if (pluginAssetSchemeEnabled) {
        expect(
          _allowed(rules, '$pluginAssetScheme://test.plugin/index.html'),
          isTrue,
        );
        expect(
          _allowed(rules, '$pluginAssetScheme://other.plugin/index.html'),
          isFalse,
        );
      } else {
        expect(_allowed(rules, 'file:///plugins/test/index.html'), isTrue);
      }
    });

    test('קידומת עם תו שאינו בטוח לביטוי נפסלת ולא מותרת', () async {
      final unsafe = buildPluginContentBlockers(
        pluginId: 'test.plugin',
        fileServerPort: 53111,
        policy: const PluginNetworkPolicy(
          prefixes: ['https://api.example.com/a{b}'],
        ),
      );

      expect(_allowed(unsafe, 'https://api.example.com/a{b}/c'), isFalse);
    });

    test('שרת פיתוח מותר לפי ה-origin שלו', () {
      final dev = buildPluginContentBlockers(
        pluginId: 'test.plugin',
        fileServerPort: 53111,
        policy: PluginNetworkPolicy.none,
        devServerOrigin: 'http://localhost:5173',
      );

      expect(_allowed(dev, 'http://localhost:5173/src/main.ts'), isTrue);
      expect(_allowed(dev, 'ws://localhost:5173/'), isTrue);
      expect(_allowed(dev, 'http://localhost:5174/'), isFalse);
    });
  });
}
