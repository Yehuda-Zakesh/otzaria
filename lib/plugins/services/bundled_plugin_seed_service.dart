import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_ids.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

/// רושמת את התוספים שחבילת ההתקנה ארזה, כדי שיהיו מותקנים כבר בפתיחה
/// הראשונה. בדסקטופ הארכיונים יושבים ליד ה-executable (במק ב-Contents/
/// Resources); במובייל אין תיקייה
/// כזו והם נארזים כ-assets בתוך החבילה. אחרי כל עדכון תוכנה משדרגת גם
/// תוספים מצורפים מותקנים שהארכיון שלהם חדש יותר. ראה docs/bundled_plugins.md.
class BundledPluginSeedService {
  /// מבחין בין "לא הועבר" (ברירת המחדל של הפלטפורמה) לבין `null` מפורש
  /// (מצב assets) — נדרש לבדיקות שרצות על דסקטופ ומדמות מובייל.
  static const Object _defaultBundleDir = Object();

  /// תיקיית ה-assets של הארכיונים במובייל — חייבת להתאים ל-pubspec.yaml.
  static const String bundledPluginsAssetDir = 'assets/bundled_plugins';

  final PluginRegistryRepository _repository;
  final PluginInstallerService _installerService;
  final Set<String> _allowedIds;
  final String? _bundleDirPath;
  final AssetBundle _assetBundle;
  final Set<String> _networkGatedIds;
  final Future<bool> Function() _isSiteReachable;

  BundledPluginSeedService({
    PluginRegistryRepository? repository,
    PluginInstallerService? installerService,
    Set<String>? allowedIds,
    Object? bundleDirPath = _defaultBundleDir,
    AssetBundle? assetBundle,
    Set<String>? networkGatedIds,
    Future<bool> Function()? isSiteReachable,
  }) : _repository = repository ?? PluginRegistryRepository(),
       _installerService =
           installerService ?? PluginInstallerService(repository: repository),
       // הזהות בצד האפליקציה היא מזהי המניפסט; מזהי החנות משמשים רק להורדה.
       _allowedIds =
           allowedIds ?? bundledPluginIdsForPlatform(Platform.operatingSystem),
       _bundleDirPath = identical(bundleDirPath, _defaultBundleDir)
           ? AppPaths.getBundledPluginsPath()
           : bundleDirPath as String?,
       _assetBundle = assetBundle ?? rootBundle,
       // ב-Windows המתקין כבר סינן: הארכיון קיים רק אם הייתה רשת בהתקנה.
       _networkGatedIds =
           networkGatedIds ??
           (Platform.isWindows ? const {} : networkGatedBundledPluginIds),
       _isSiteReachable = isSiteReachable ?? _otzariaSiteReturnsOk;

  static Future<bool> _otzariaSiteReturnsOk() async {
    // הבדיקה שייכת לחלון הראשי — אחרת כל חלון נוסף שולח בקשה משלו.
    if (WindowRole.isSecondary ||
        (Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false)) {
      return false;
    }
    try {
      final response = await http
          .get(Uri.parse('https://otzaria.org/'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// מחזירה `true` אם נרשם או שודרג תוסף — ואז על הקורא לרענן את הרשימה.
  Future<bool> seedPending() async {
    if (_allowedIds.isEmpty) return false;

    final seeded = _readSeededIds();
    final initialSeededCount = seeded.length;
    // הארכיונים מתחלפים רק עם התוכנה, ולכן בדיקת השדרוג רצה פעם אחת לגרסה.
    final appVersion = appReleaseVersion(await PackageInfo.fromPlatform());
    final checkUpgrades =
        Settings.getValue<String>(
          SettingsRepository.keyBundledPluginsUpgradeCheckedVersion,
        ) !=
        appVersion;
    var registered = false;
    Directory? assetStagingDir;
    Future<bool>? siteReachable;

    try {
      for (final pluginId in _allowedIds) {
        final installed = await _repository.getPlugin(pluginId);
        if (installed != null) {
          // מותקן כבר, אולי ע"י המשתמש — אין התקנה ראשונה, רק שדרוג.
          seeded.add(pluginId);
          if (!checkUpgrades || installed.isDevelopment) continue;
        } else if (seeded.contains(pluginId)) {
          // המשתמש הסיר — לא מחזירים.
          continue;
        }

        final String archivePath;
        final bundleDir = _bundleDirPath;
        if (bundleDir != null) {
          final archive = File(p.join(bundleDir, '$pluginId.otzplugin'));
          if (!await archive.exists()) continue;
          archivePath = archive.path;
        } else {
          // מובייל: הארכיון נארז כ-asset ומועתק לקובץ זמני לצורך ההתקנה.
          assetStagingDir ??= await Directory.systemTemp.createTemp(
            'otz_bundled_assets_',
          );
          final staged = await _stageAssetArchive(pluginId, assetStagingDir);
          if (staged == null) continue;
          archivePath = staged;
        }

        // לא מסומן כמטופל — ינוסה שוב בעלייה הבאה, כשאולי יש רשת.
        if (installed == null &&
            _networkGatedIds.contains(pluginId) &&
            !await (siteReachable ??= _isSiteReachable())) {
          continue;
        }

        if (await _install(
          pluginId,
          archivePath,
          previousPlugin: installed,
        )) {
          seeded.add(pluginId);
          registered = true;
        }
      }
    } finally {
      if (assetStagingDir != null && assetStagingDir.existsSync()) {
        assetStagingDir.deleteSync(recursive: true);
      }
    }

    if (seeded.length != initialSeededCount) {
      await Settings.setValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        seeded.join(','),
      );
    }
    // גם אחרי שדרוג שנכשל: אחרת כל עלייה הייתה מחלצת שוב את כל הארכיונים.
    if (checkUpgrades) {
      await Settings.setValue<String>(
        SettingsRepository.keyBundledPluginsUpgradeCheckedVersion,
        appVersion,
      );
    }
    return registered;
  }

  /// כותבת את ה-asset לקובץ זמני; `null` כשהארכיון לא נארז בחבילה זו.
  Future<String?> _stageAssetArchive(
    String pluginId,
    Directory stagingDir,
  ) async {
    try {
      final data = await _assetBundle.load(
        '$bundledPluginsAssetDir/$pluginId.otzplugin',
      );
      final file = File(p.join(stagingDir.path, '$pluginId.otzplugin'));
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _install(
    String pluginId,
    String archivePath, {
    required InstalledPlugin? previousPlugin,
  }) async {
    final isUpgrade = previousPlugin != null;
    try {
      final prepared = await _installerService.prepareInstall(archivePath);
      // המזהה שברשימת ההיתר הוא מה שאושר, לא שם הקובץ: ארכיון שמצהיר על
      // מזהה אחר נדחה, אחרת החלפת קובץ הייתה מתקינה תוסף שלא אושר.
      if (prepared.manifest.id != pluginId) {
        await _installerService.cancelInstall(prepared.tempDirPath);
        debugPrint(
          'Bundled plugin id mismatch: archive "$pluginId.otzplugin" '
          'declares "${prepared.manifest.id}"',
        );
        return false;
      }

      final previousGrants = prepared.previousGrantedPermissions;
      final isOfflineMode =
          Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;
      final grantedPermissions = {
        for (final permission in effectiveManifestPermissions(
          prepared.manifest.permissions,
        ))
          permission:
              previousGrants[permission] ??
              previousGrants[pluginLegacyPermissionAliases[permission]] ??
              // בשדרוג הרשאה חדשה מקבלת את ברירת המחדל של דיאלוג העדכון.
              (!isUpgrade ||
                  pluginPermissionDefaultGrant(
                    permission,
                    isOfflineMode: isOfflineMode,
                  )),
      };
      await _installerService.finalizeInstall(
        prepared.tempDirPath,
        prepared.manifest,
        grantedPermissions: grantedPermissions,
        expectedPlugin: previousPlugin,
        expectedPermissions: previousGrants,
      );
      if (isUpgrade && grantedPermissions['navigation.write'] != true) {
        PluginNewTabPageRegistry.instance.remove(pluginId);
        PluginNewTabPageService.broadcastChanged();
      }
      return true;
    } on PluginOverwriteException {
      return false; // הגרסה המצורפת כבר מותקנת
    } on PluginNewerVersionInstalledException {
      return false;
    } catch (e) {
      // שקט בכוונה: ההתקנה אוטומטית, ועדכון שנכשל עדיין זמין בחנות.
      debugPrint('Bundled plugin seed failed [$pluginId]: $e');
      return false;
    }
  }

  Set<String> _readSeededIds() {
    final raw = Settings.getValue<String>(
      SettingsRepository.keySeededBundledPlugins,
      defaultValue: '',
    );
    return (raw ?? '')
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}
