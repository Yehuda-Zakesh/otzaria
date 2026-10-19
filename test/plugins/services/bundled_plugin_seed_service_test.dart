import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';

class FakeRepository extends Mock implements PluginRegistryRepository {
  final Map<String, InstalledPlugin> plugins = {};
  final Map<String, Map<String, bool>> permissions = {};
  final List<String> savedIds = [];

  @override
  Future<InstalledPlugin?> getPlugin(String id) async => plugins[id];

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(
    String pluginId,
  ) async => [
    for (final entry in (permissions[pluginId] ?? const {}).entries)
      PluginPermissionGrant(
        pluginId: pluginId,
        permission: entry.key,
        granted: entry.value,
        grantedAt: DateTime(2024),
      ),
  ];

  @override
  Future<void> savePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
  ) async {
    plugins[plugin.pluginId] = plugin;
    this.permissions[plugin.pluginId] = permissions;
    savedIds.add(plugin.pluginId);
  }

  @override
  Future<void> upgradePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
    InstalledPlugin expectedPlugin,
    Map<String, bool> expectedPermissions,
  ) async {
    if (!mapEquals(
      plugins[plugin.pluginId]?.toDbMap(),
      expectedPlugin.toDbMap(),
    )) {
      throw StateError('Plugin changed during bundled upgrade');
    }
    await savePluginWithPermissions(plugin, permissions);
  }

  @override
  Future<int?> getNextUserOrderForNewPlugin() async => null;
}

Map<String, dynamic> manifestJson(
  String pluginId, {
  String version = '1.0.0',
  List<String> permissions = const [],
}) => {
  'schemaVersion': 1,
  'id': pluginId,
  'version': version,
  'name': 'Bundled',
  'entrypoint': 'index.html',
  if (permissions.isNotEmpty) 'permissions': permissions,
};

InstalledPlugin installedPlugin(
  String pluginId,
  String installPath, {
  String version = '1.0.0',
  List<String> permissions = const [],
}) {
  return InstalledPlugin(
    pluginId: pluginId,
    name: 'Bundled',
    version: version,
    installPath: installPath,
    entrypointPath: 'index.html',
    enabled: true,
    pinned: false,
    manifest: PluginManifest.fromJson(
      manifestJson(pluginId, version: version, permissions: permissions),
    ),
    installedAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

List<int> pluginArchiveBytes(
  String pluginId, {
  String version = '1.0.0',
  List<String> permissions = const [],
  String? minAppVersion,
}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(
          {
            ...manifestJson(
              pluginId,
              version: version,
              permissions: permissions,
            ),
            'minAppVersion': ?minAppVersion,
          },
        ),
      ),
    )
    ..addFile(ArchiveFile.string('index.html', '<html></html>'));
  return ZipEncoder().encode(archive);
}

void writePluginArchive(
  String path,
  String pluginId, {
  String version = '1.0.0',
  List<String> permissions = const [],
  String? minAppVersion,
}) {
  File(path).writeAsBytesSync(
    pluginArchiveBytes(
      pluginId,
      version: version,
      permissions: permissions,
      minAppVersion: minAppVersion,
    ),
  );
}

/// מדמה את ה-assets של APK — ארכיונים לפי מפתח, וזריקה על מפתח חסר
/// כמו rootBundle.
class FakeAssetBundle extends CachingAssetBundle {
  final Map<String, List<int>> files = {};

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('Unable to load asset: $key');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Otzaria',
    packageName: 'com.otzaria.app',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  late Directory tempDir;
  late Directory bundleDir;
  late FakeRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = Directory.systemTemp.createTempSync('otzaria_bundled_seed_');
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data'));
    bundleDir = Directory(p.join(tempDir.path, 'bundled_plugins'))
      ..createSync();
    repository = FakeRepository();
  });

  tearDown(() {
    AppPaths.debugOverrideDataRootPath(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  BundledPluginSeedService buildService(Set<String> allowedIds) {
    return BundledPluginSeedService(
      repository: repository,
      allowedIds: allowedIds,
      bundleDirPath: bundleDir.path,
    );
  }

  test('מתקין תוסף מהרשימה שארכיונו קיים ומסמן אותו כמטופל', () async {
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'test.bundled',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isTrue);
    expect(repository.savedIds, ['test.bundled']);
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      'test.bundled',
    );
  });

  test('תוסף שסומן כמטופל אינו מותקן שוב — גם אחרי שהמשתמש הסיר', () async {
    await Settings.setValue<String>(
      SettingsRepository.keySeededBundledPlugins,
      'test.bundled',
    );
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'test.bundled',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
  });

  test('ארכיון שאינו ברשימת ההיתר אינו מותקן', () async {
    writePluginArchive(
      p.join(bundleDir.path, 'not.allowed.otzplugin'),
      'not.allowed',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
  });

  test('ארכיון שמצהיר מזהה שונה משם הקובץ נדחה', () async {
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'some.other.plugin',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
    // כשל אינו מסומן כמטופל — אבל גם לא מנוסה בלולאה באותה קריאה.
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      '',
    );
  });

  test('תוסף שכבר מותקן מסומן כמטופל בלי להתקין מחדש', () async {
    repository.plugins['test.bundled'] = installedPlugin(
      'test.bundled',
      p.join(tempDir.path, 'existing'),
      version: '2.0.0',
    );
    writePluginArchive(
      p.join(bundleDir.path, 'test.bundled.otzplugin'),
      'test.bundled',
    );

    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(repository.savedIds, isEmpty);
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      'test.bundled',
    );
  });

  group('שדרוג תוסף מצורף שכבר מותקן', () {
    const checkedKey =
        SettingsRepository.keyBundledPluginsUpgradeCheckedVersion;

    setUp(() async {
      await Settings.setValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        'test.bundled',
      );
      repository.plugins['test.bundled'] = installedPlugin(
        'test.bundled',
        p.join(tempDir.path, 'existing'),
        permissions: ['app.open_url'],
      );
      repository.permissions['test.bundled'] = {'app.open_url': false};
      writePluginArchive(
        p.join(bundleDir.path, 'test.bundled.otzplugin'),
        'test.bundled',
        version: '2.0.0',
        permissions: ['app.open_url', 'app.user_email.read'],
      );
    });

    test('ארכיון חדש יותר משדרג, שומר סירוב ומעניק הרשאה חדשה', () async {
      final registered = await buildService({'test.bundled'}).seedPending();

      expect(registered, isTrue);
      expect(repository.plugins['test.bundled']!.version, '2.0.0');
      expect(repository.permissions['test.bundled'], {
        'app.open_url': false,
        'app.user_email.read': true,
      });
      expect(Settings.getValue<String>(checkedKey), '1.0.0');
    });

    test('בגרסת תוכנה שכבר נבדקה אין בדיקת שדרוג', () async {
      await Settings.setValue<String>(checkedKey, '1.0.0');

      final registered = await buildService({'test.bundled'}).seedPending();

      expect(registered, isFalse);
      expect(repository.savedIds, isEmpty);
    });

    test('תוסף שהמשתמש הסיר אינו חוזר גם כשהארכיון חדש יותר', () async {
      repository.plugins.clear();

      final registered = await buildService({'test.bundled'}).seedPending();

      expect(registered, isFalse);
      expect(repository.savedIds, isEmpty);
    });

    test('שדרוג שנכשל מסמן את הגרסה — בלי חילוץ חוזר בכל עלייה', () async {
      writePluginArchive(
        p.join(bundleDir.path, 'test.bundled.otzplugin'),
        'some.other.plugin',
        version: '2.0.0',
      );

      final registered = await buildService({'test.bundled'}).seedPending();

      expect(registered, isFalse);
      expect(repository.savedIds, isEmpty);
      expect(Settings.getValue<String>(checkedKey), '1.0.0');
    });

    test('גרסה זהה אינה מותקנת מחדש ומסמנת את הגרסה', () async {
      writePluginArchive(
        p.join(bundleDir.path, 'test.bundled.otzplugin'),
        'test.bundled',
        permissions: ['app.open_url'],
      );

      final registered = await buildService({'test.bundled'}).seedPending();

      expect(registered, isFalse);
      expect(repository.savedIds, isEmpty);
      expect(Settings.getValue<String>(checkedKey), '1.0.0');
    });

    test('הרשאה חדשה שכבויה כברירת מחדל נשארת כבויה בשדרוג', () async {
      writePluginArchive(
        p.join(bundleDir.path, 'test.bundled.otzplugin'),
        'test.bundled',
        version: '2.0.0',
        permissions: ['app.open_url', 'clipboard.read'],
      );

      await buildService({'test.bundled'}).seedPending();

      expect(repository.permissions['test.bundled'], {
        'app.open_url': false,
        'clipboard.read': false,
      });
    });

    test('תוסף שהמשתמש התקין בעצמו משודרג ומסומן כמטופל', () async {
      await Settings.setValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        '',
      );

      final registered = await buildService({'test.bundled'}).seedPending();

      expect(registered, isTrue);
      expect(repository.plugins['test.bundled']!.version, '2.0.0');
      expect(
        Settings.getValue<String>(SettingsRepository.keySeededBundledPlugins),
        'test.bundled',
      );
    });
  });

  test('ארכיון חסר אינו מסומן כמטופל — ינוסה שוב בעלייה הבאה', () async {
    final registered = await buildService({'test.bundled'}).seedPending();

    expect(registered, isFalse);
    expect(
      Settings.getValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        defaultValue: '',
      ),
      '',
    );
  });

  group('תוסף שתלוי ברשת — נרשם רק כש-otzaria.org עונה 200', () {
    BundledPluginSeedService buildGatedService({
      Future<bool> Function()? isSiteReachable,
    }) {
      return BundledPluginSeedService(
        repository: repository,
        allowedIds: {'test.bundled'},
        bundleDirPath: bundleDir.path,
        networkGatedIds: {'test.bundled'},
        isSiteReachable: isSiteReachable,
      );
    }

    setUp(() {
      writePluginArchive(
        p.join(bundleDir.path, 'test.bundled.otzplugin'),
        'test.bundled',
      );
    });

    test('בלי תשובת 200 אינו מותקן ואינו מסומן — ינוסה שוב', () async {
      final registered = await buildGatedService(
        isSiteReachable: () async => false,
      ).seedPending();

      expect(registered, isFalse);
      expect(repository.savedIds, isEmpty);
      expect(
        Settings.getValue<String>(
          SettingsRepository.keySeededBundledPlugins,
          defaultValue: '',
        ),
        '',
      );
    });

    test('עם תשובת 200 מותקן ומסומן כמטופל', () async {
      final registered = await buildGatedService(
        isSiteReachable: () async => true,
      ).seedPending();

      expect(registered, isTrue);
      expect(repository.savedIds, ['test.bundled']);
    });

    test('במצב "ללא גישה לאינטרנט" אינו מותקן, בלי בקשת רשת', () async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);

      final registered = await buildGatedService().seedPending();

      expect(registered, isFalse);
      expect(repository.savedIds, isEmpty);
    });
  });

  group('מובייל — ארכיונים מ-assets (אין תיקייה ליד ה-executable)', () {
    BundledPluginSeedService buildAssetService(
      Set<String> allowedIds,
      FakeAssetBundle bundle,
    ) {
      return BundledPluginSeedService(
        repository: repository,
        allowedIds: allowedIds,
        bundleDirPath: null,
        assetBundle: bundle,
      );
    }

    test('מתקין תוסף שארכיונו נארז כ-asset ומסמן אותו כמטופל', () async {
      final bundle = FakeAssetBundle();
      bundle.files['${BundledPluginSeedService.bundledPluginsAssetDir}/'
          'test.bundled.otzplugin'] = pluginArchiveBytes(
        'test.bundled',
      );

      final registered = await buildAssetService({
        'test.bundled',
      }, bundle).seedPending();

      expect(registered, isTrue);
      expect(repository.savedIds, ['test.bundled']);
      expect(
        Settings.getValue<String>(
          SettingsRepository.keySeededBundledPlugins,
          defaultValue: '',
        ),
        'test.bundled',
      );
    });

    test('asset חסר אינו מסומן כמטופל ואינו מפיל את השאר', () async {
      final bundle = FakeAssetBundle();
      bundle.files['${BundledPluginSeedService.bundledPluginsAssetDir}/'
          'test.bundled.otzplugin'] = pluginArchiveBytes(
        'test.bundled',
      );

      final registered = await buildAssetService({
        'missing.plugin',
        'test.bundled',
      }, bundle).seedPending();

      expect(registered, isTrue);
      expect(repository.savedIds, ['test.bundled']);
      expect(
        Settings.getValue<String>(
          SettingsRepository.keySeededBundledPlugins,
          defaultValue: '',
        ),
        'test.bundled',
      );
    });
  });
}
