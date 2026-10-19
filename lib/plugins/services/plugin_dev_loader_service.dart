import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';

bool _isLocalhostUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

class PluginDevLoaderService {
  final PluginRegistryRepository _repository;

  PluginDevLoaderService({PluginRegistryRepository? repository})
    : _repository = repository ?? PluginRegistryRepository();

  Future<void> _validateDevelopmentManifest(
    PluginManifest manifest,
    String directoryPath, {
    required Map<String, dynamic> manifestJson,
    bool skipFileValidation = false,
  }) async {
    // תוסף פיתוח פטור מבדיקת תאימות גרסה כדי לאפשר בדיקה מול גרסאות עתידיות.
    await PluginManifestValidator.validateManifest(
      manifest: manifest,
      directoryPath: directoryPath,
      skipFileValidation: skipFileValidation,
      skipAppVersionValidation: true,
    );
    // ב-localhost ה"תיקייה" היא URL — Directory.existsSync עליו זורק ב-Windows.
    final scanPath = skipFileValidation ? null : directoryPath;
    final report = await Isolate.run(
      () => PluginExtendedValidator.validate(
        manifest: manifest,
        manifestJson: manifestJson,
        directoryPath: scanPath,
      ),
    );
    if (report.hasErrors) throw Exception(report.errors.join('\n'));
  }

  /// קורא את manifest.json מתיקייה ומאמת אותו. לא שומר לDB.
  Future<PluginManifest> fetchDevelopmentManifest(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw Exception('תיקיית התוסף לא נמצאה: $directoryPath');
    }
    final manifestFile = File(p.join(directoryPath, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw Exception('manifest.json לא נמצא בתיקיית התוסף');
    }
    final manifestStr = manifestFile.readAsStringSync();
    final manifestJson = Map<String, dynamic>.from(
      jsonDecode(manifestStr) as Map,
    );
    final manifest = PluginManifest.fromJson(manifestJson);
    await _validateDevelopmentManifest(
      manifest,
      directoryPath,
      manifestJson: manifestJson,
    );
    return manifest;
  }

  /// [preValidatedManifest] — מניפסט שכבר אומת (למשל, שהוצג בדיאלוג הרשאות).
  /// כשמסופק, אין קריאה חוזרת מהדיסק — מונע התקנת הרשאות שלא הוצגו למשתמש.
  Future<void> loadDevelopmentPlugin(
    String directoryPath, {
    PluginManifest? preValidatedManifest,
    Map<String, bool>? grantedPermissions,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw Exception('תיקיית התוסף לא נמצאה: $directoryPath');
    }

    final PluginManifest manifest;
    if (preValidatedManifest != null) {
      manifest = preValidatedManifest;
    } else {
      final manifestFile = File(p.join(directoryPath, 'manifest.json'));
      if (!manifestFile.existsSync()) {
        throw Exception('manifest.json לא נמצא בתיקיית התוסף');
      }
      final manifestStr = manifestFile.readAsStringSync();
      final manifestJson = Map<String, dynamic>.from(
        jsonDecode(manifestStr) as Map,
      );
      manifest = PluginManifest.fromJson(manifestJson);
      await _validateDevelopmentManifest(
        manifest,
        directoryPath,
        manifestJson: manifestJson,
      );
    }

    final existingPlugin = await _repository.getPlugin(manifest.id);
    if (existingPlugin != null && !existingPlugin.isDevelopment) {
      throw Exception(
        'כבר קיים תוסף מותקן (רגיל) עם אותו מזהה. מחק או שנה id.',
      );
    }

    // טעינה-מחדש של תוסף פיתוח: שומרים את הסדר הידני.
    // טעינה ראשונה: אם כבר יש תוספים שסודרו ידנית, מצטרפים לסוף הסדר.
    final newUserOrder = existingPlugin != null
        ? existingPlugin.userOrder
        : await _repository.getNextUserOrderForNewPlugin();

    final plugin = InstalledPlugin(
      pluginId: manifest.id,
      name: manifest.name,
      version: manifest.version,
      installPath: directoryPath,
      entrypointPath: manifest.entrypoint,
      iconPath: manifest.icon,
      enabled: existingPlugin?.enabled ?? true,
      pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
      pinnedToNavRail: existingPlugin?.pinnedToNavRail ?? false,
      manifest: manifest,
      installedAt: existingPlugin?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      sourceType: 'development',
      devRootPath: directoryPath,
      userOrder: newUserOrder,
    );

    final permissions = await _resolvePermissionDecisions(
      manifest,
      existingPlugin,
      grantedPermissions,
    );
    await _repository.saveDevelopmentPluginWithPermissions(
      plugin,
      permissions,
    );
  }

  /// טוען manifest.json מ-localhost ומאמת אותו. לא שומר לDB.
  Future<PluginManifest> fetchLocalhostManifest(String baseUrl) async {
    final normalizedUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (!_isLocalhostUri(normalizedUrl)) {
      throw Exception('כתובת localhost בלבד נתמכת (localhost / 127.0.0.1)');
    }
    final client = HttpClient();
    try {
      final HttpClientRequest request;
      try {
        request = await client.getUrl(
          Uri.parse('$normalizedUrl/manifest.json'),
        );
      } on SocketException {
        throw Exception('לא ניתן להתחבר ל-$normalizedUrl — ודא ששרת הפיתוח רץ');
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
          'לא ניתן לטעון manifest.json — קוד שגיאה ${response.statusCode}',
        );
      }
      final manifestStr = await response.transform(const Utf8Decoder()).join();
      // SPA dev servers return index.html as fallback for unknown paths
      if (manifestStr.trimLeft().startsWith('<')) {
        throw Exception(
          'השרת החזיר HTML במקום manifest.json.\n'
          'הוסף את manifest.json לתיקיית הנכסים הסטטיים:\n'
          '• Vite: תיקיית public/\n'
          '• webpack: תיקיית static/ או CopyWebpackPlugin',
        );
      }
      final manifestJson = Map<String, dynamic>.from(
        jsonDecode(manifestStr) as Map,
      );
      final manifest = PluginManifest.fromJson(manifestJson);
      await _validateDevelopmentManifest(
        manifest,
        normalizedUrl,
        manifestJson: manifestJson,
        skipFileValidation: true,
      );
      return manifest;
    } finally {
      client.close();
    }
  }

  /// [preValidatedManifest] — מניפסט שכבר אומת (למשל, שהוצג בדיאלוג הרשאות).
  /// כשמסופק, אין fetch חוזר מהשרת — מונע התקנת הרשאות שלא הוצגו למשתמש.
  Future<void> loadLocalhostPlugin(
    String baseUrl, {
    PluginManifest? preValidatedManifest,
    Map<String, bool>? grantedPermissions,
  }) async {
    final normalizedUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final manifest =
        preValidatedManifest ?? await fetchLocalhostManifest(normalizedUrl);

    final existingPlugin = await _repository.getPlugin(manifest.id);
    if (existingPlugin != null && !existingPlugin.isDevelopment) {
      throw Exception(
        'כבר קיים תוסף מותקן (רגיל) עם אותו מזהה. מחק או שנה id.',
      );
    }

    final newUserOrder = existingPlugin != null
        ? existingPlugin.userOrder
        : await _repository.getNextUserOrderForNewPlugin();

    final plugin = InstalledPlugin(
      pluginId: manifest.id,
      name: manifest.name,
      version: manifest.version,
      installPath: normalizedUrl,
      entrypointPath: manifest.entrypoint,
      iconPath: manifest.icon,
      enabled: existingPlugin?.enabled ?? true,
      pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
      pinnedToNavRail: existingPlugin?.pinnedToNavRail ?? false,
      manifest: manifest,
      installedAt: existingPlugin?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      sourceType: 'localhost_dev',
      devRootPath: normalizedUrl,
      userOrder: newUserOrder,
    );

    final permissions = await _resolvePermissionDecisions(
      manifest,
      existingPlugin,
      grantedPermissions,
    );
    await _repository.saveDevelopmentPluginWithPermissions(
      plugin,
      permissions,
    );
  }

  Future<Map<String, bool>> _resolvePermissionDecisions(
    PluginManifest manifest,
    InstalledPlugin? existingPlugin,
    Map<String, bool>? explicitDecisions,
  ) async {
    final effectivePermissions = effectiveManifestPermissions(
      manifest.permissions,
    );
    final requested = effectivePermissions.toSet();
    if (explicitDecisions != null) {
      final supplied = explicitDecisions.keys.toSet();
      if (supplied.difference(requested).isNotEmpty ||
          requested.difference(supplied).isNotEmpty) {
        throw ArgumentError(
          'Permission decisions must exactly match manifest permissions',
        );
      }
      return Map.unmodifiable(explicitDecisions);
    }

    final existingGrants = <String, bool>{};
    if (existingPlugin != null) {
      for (final permission in effectiveManifestPermissions(
        existingPlugin.manifest.permissions,
      )) {
        final granted = await _repository.getPermission(
          manifest.id,
          permission,
        );
        if (granted != null) existingGrants[permission] = granted;
      }
    }
    return Map.unmodifiable({
      for (final permission in effectivePermissions)
        permission: existingGrants[permission] ?? (existingPlugin == null),
    });
  }
}
