import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/plugins/view/plugin_new_tab_page_choice.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: id == 'a' ? 'ראשון' : 'שני',
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': ['navigation.write'],
  }),
);

class _Repository extends Fake implements PluginRegistryRepository {
  final plugins = {'a': _plugin('a'), 'b': _plugin('b')};
  final grants = <String, Map<String, bool>>{
    'a': {'navigation.write': true},
    'b': {'navigation.write': true},
  };
  Future<void>? beforeGrant;
  var grantStarted = Completer<void>();

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => plugins[id];
  @override
  Future<bool?> getPermission(String id, String permission) async =>
      grants[id]?[permission];
  @override
  Future<void> setPermission(String id, String permission, bool granted) async {
    grants[id]![permission] = granted;
  }

  @override
  Future<void> clearNewTabPageRegistration(String id) async {
    if (grants[id]?[pluginNewTabPagePermission] == true) {
      grants[id]!.remove(pluginNewTabPagePermission);
    }
  }

  @override
  Future<String?> getNewTabPageOwner() async {
    for (final id in plugins.keys) {
      if (plugins[id]!.enabled &&
          grants[id]?['navigation.write'] == true &&
          grants[id]?[pluginNewTabPagePermission] == true) {
        return id;
      }
    }
    return null;
  }

  @override
  Future<bool> grantNewTabPage(
    String id, {
    required bool allowPreviouslyDenied,
    required String? expectedOwner,
    required void Function() onGranted,
  }) async {
    if (!grantStarted.isCompleted) grantStarted.complete();
    await beforeGrant;
    if (await getNewTabPageOwner() != expectedOwner ||
        plugins[id]?.enabled != true ||
        grants[id]?['navigation.write'] != true ||
        (!allowPreviouslyDenied &&
            grants[id]?[pluginNewTabPagePermission] == false)) {
      return false;
    }
    for (final values in grants.values) {
      if (values.containsKey(pluginNewTabPagePermission)) {
        values[pluginNewTabPagePermission] = false;
      }
    }
    grants[id]![pluginNewTabPagePermission] = true;
    onGranted();
    return true;
  }
}

void main() {
  final registry = PluginNewTabPageRegistry.instance;
  late _Repository repo;
  late PluginNewTabPageService service;
  late List<String> conflicts;

  setUp(() async {
    repo = _Repository();
    service = PluginNewTabPageService();
    conflicts = [];
    await Future<void>.value();
  });
  tearDown(() {
    registry.remove('a');
    registry.remove('b');
    UiSnack.hide();
  });
  Future<bool> request(String id) =>
      service.request(id, repo, onConflict: conflicts.add);

  test('תוסף ניווט רגיל אינו מקבל החלטת כפתור בלי בקשה', () {
    expect(repo.grants['a']!.containsKey(pluginNewTabPagePermission), isFalse);
    expect(registry.hasActiveRegistration, isFalse);
  });
  test('הבעלים הראשון נשמר ורישום חוזר אינו משנה את הממשק', () async {
    var notifications = 0;
    void listener() => notifications++;
    registry.addListener(listener);
    addTearDown(() => registry.removeListener(listener));
    expect(await request('a'), isTrue);
    expect(await request('a'), isTrue);
    expect(repo.grants['a']![pluginNewTabPagePermission], isTrue);
    expect(notifications, 1);
  });
  test('מתחרה מקבל false ואזהרה פעם אחת; ניווט שלו נשאר מאושר', () async {
    await request('a');
    expect(await request('b'), isFalse);
    expect(await request('b'), isFalse);
    expect(conflicts, ['a']);
    expect(repo.grants['b']!['navigation.write'], isTrue);
    expect(repo.grants['b']![pluginNewTabPagePermission], isFalse);
    registry.remove('a');
    expect(registry.hasActiveRegistration, isFalse);
  });
  test(
    'בחירת המשתמש מחליפה בעלות ולא מאפשרת לבעלים הקודם להשתלט שוב',
    () async {
      await request('a');
      await request('b');
      expect(await service.grant('b', repo, expectedOwner: 'a'), isTrue);
      expect(registry.activePluginId, 'b');
      expect(repo.grants['a']![pluginNewTabPagePermission], isFalse);
      expect(repo.grants['a']!['navigation.write'], isTrue);
      expect(await request('a'), isFalse);
    },
  );
  test('בעלות שמורה מגנה על הבחירה גם לפני רישום מחדש אחרי restart', () async {
    await request('a');
    registry.remove('a');
    expect(await request('b'), isFalse);
    expect(conflicts, ['a']);
    expect(await request('a'), isTrue);
    expect(registry.activePluginId, 'a');
  });
  test('שחרור מפורש מאפשר בקשה חדשה בלי להעמיד מתחרה בתור', () async {
    await request('a');
    await service.release('a', repo);
    expect(registry.hasActiveRegistration, isFalse);
    expect(await request('b'), isTrue);
  });
  test('שחרור אינו עוקף חסימה מפורשת של המשתמש', () async {
    await request('a');
    await request('b');
    await service.release('b', repo);
    expect(await request('b'), isFalse);
    expect(repo.grants['b']![pluginNewTabPagePermission], isFalse);
    expect(conflicts, ['a']);
  });
  test('אי אפשר להעניק כפתור לתוסף שלא ביקש אותו', () async {
    expect(await service.grant('b', repo, expectedOwner: 'a'), isFalse);
    expect(registry.hasActiveRegistration, isFalse);
  });
  for (final revoke in [
    'navigation.write',
    pluginNewTabPagePermission,
    'disable',
  ]) {
    test('שלילת $revoke בזמן הענקה אינה משאירה בעלות מאוחרת', () async {
      final gate = Completer<void>();
      repo.beforeGrant = gate.future;
      final pending = request('a');
      await repo.grantStarted.future;
      if (revoke == 'disable') {
        repo.plugins['a'] = repo.plugins['a']!.copyWith(enabled: false);
      } else {
        repo.grants['a']![revoke] = false;
      }
      registry.remove('a');
      gate.complete();
      expect(await pending, isFalse);
      expect(registry.hasActiveRegistration, isFalse);
    });
  }
  test('שחרור שמגיע בזמן רישום רץ אחריו ומשאיר כפתור פנוי', () async {
    final gate = Completer<void>();
    repo.beforeGrant = gate.future;
    final pending = request('a');
    await repo.grantStarted.future;
    final released = service.release('a', repo);
    gate.complete();
    expect(await pending, isTrue);
    await released;
    expect(registry.hasActiveRegistration, isFalse);
    expect(await request('b'), isTrue);
  });

  Future<void> pumpApp(WidgetTester tester) {
    PluginNewTabPageService.instance.resetQueueForTesting();
    service = PluginNewTabPageService();
    return tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SizedBox()),
        ),
      ),
    );
  }

  testWidgets('התנגשות מציגה הודעה ובחירה נפתחת רק בלחיצת משתמש', (
    tester,
  ) async {
    await pumpApp(tester);
    await request('a');
    await request('b');
    await notifyPluginNewTabPageConflict(repo.plugins['b']!, 'a', repo);
    await tester.pumpAndSettle();
    expect(find.textContaining('שכבר ניתן'), findsOneWidget);
    expect(find.text('בחירת תוסף לכפתור לשונית חדשה (+)'), findsNothing);
    await tester.tap(find.text('בחר תוסף'));
    await tester.pumpAndSettle();
    expect(find.text('בחירת תוסף לכפתור לשונית חדשה (+)'), findsOneWidget);
    await tester.tap(find.text('הענק לשני'));
    await tester.pumpAndSettle();
    expect(registry.activePluginId, 'b');
    expect(repo.grants['a']![pluginNewTabPagePermission], isFalse);
    expect(repo.grants['a']!['navigation.write'], isTrue);
  });
  testWidgets('בחירה פועלת גם כשהבעלות רק שמורה לפני רישום אחרי restart', (
    tester,
  ) async {
    await pumpApp(tester);
    await request('a');
    await request('b');
    registry.remove('a');
    final dialog = choosePluginNewTabPage(
      navigatorKey.currentContext!,
      repo.plugins['b']!,
      repo,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('הענק לשני'));
    await tester.pumpAndSettle();
    expect(await dialog, isTrue);
    expect(registry.activePluginId, 'b');
  });

  testWidgets('הסכמה ישנה לא מחליפה בעלים שהשתנה בזמן הדיאלוג', (tester) async {
    await pumpApp(tester);
    await request('a');
    await request('b');
    final dialog = choosePluginNewTabPage(
      navigatorKey.currentContext!,
      repo.plugins['b']!,
      repo,
    );
    await tester.pumpAndSettle();
    repo.plugins['c'] = _plugin('c');
    repo.grants['c'] = {
      'navigation.write': true,
      pluginNewTabPagePermission: false,
    };
    expect(await service.grant('c', repo, expectedOwner: 'a'), isTrue);
    await tester.tap(find.text('הענק לשני'));
    await tester.pumpAndSettle();
    expect(await dialog, isFalse);
    expect(registry.activePluginId, 'c');
    registry.remove('c');
  });

  test('בחירה שנכנסה לתור אינה מחליפה בעלים אחר שנבחר לפני הכתיבה', () async {
    await request('a');
    await request('b');
    final gate = Completer<void>();
    repo.beforeGrant = gate.future;
    repo.grantStarted = Completer<void>();
    final pending = service.grant('b', repo, expectedOwner: 'a');
    await repo.grantStarted.future;
    repo.plugins['c'] = _plugin('c');
    repo.grants['c'] = {
      'navigation.write': true,
      pluginNewTabPagePermission: true,
    };
    repo.grants['a']![pluginNewTabPagePermission] = false;
    registry.selectOwner('c');
    gate.complete();
    expect(await pending, isFalse);
    expect(registry.activePluginId, 'c');
    registry.remove('c');
  });

  testWidgets('ביטול הבחירה משאיר את ההרשאה והבעלות הקודמות', (tester) async {
    await pumpApp(tester);
    await request('a');
    await request('b');
    final dialog = choosePluginNewTabPage(
      navigatorKey.currentContext!,
      repo.plugins['b']!,
      repo,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('השאר אצל ראשון'));
    await tester.pumpAndSettle();
    expect(await dialog, isFalse);
    expect(registry.activePluginId, 'a');
    expect(repo.grants['b']![pluginNewTabPagePermission], isFalse);
  });
}
