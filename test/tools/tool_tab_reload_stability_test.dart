import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/view/tool_tab_screen.dart';

/// בדיקות רגרסיה לבאג "התקנת תוסף מהחנות מרעננת את כל התוכן".
///
/// הרקע: כל התקנה/הצמדה/סידור מחדש מפעילה `LoadPlugins`, וה-Bloc עבר דרך
/// מצבים שאינם `PluginSystemLoaded`. `lookupTool` מחזיר במצבים כאלה `loading`,
/// ומסך הכלי החליף את התוסף בספינר — מה שהוציא את `PluginTabPage` מהעץ, הרס
/// את ה-WebView, וגרם לדף התוסף (למשל החנות עצמה) להיטען מאפס.

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: id,
    version: '1.0.0',
    description: 'test',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: id,
    toolTabOrder: 900,
    allowOrderBeforeBuiltIns: false,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

ToolLookupResult _lookup(String toolId, PluginSystemState state) => lookupTool(
  toolId,
  hiddenBuiltInToolIds: const {},
  isOfflineMode: false,
  pluginState: state,
);

void main() {
  group('resolveToolLookup', () {
    const storeId = 'otzaria.plugins_directory';

    test('טעינה ראשונה — אין כלי קודם, מוצג ספינר', () {
      final resolved = resolveToolLookup(
        _lookup(storeId, PluginSystemInitial()),
        null,
      );
      expect(
        resolved,
        isA<ToolUnavailable>().having(
          (u) => u.reason,
          'reason',
          ToolUnavailableReason.loading,
        ),
      );
    });

    test('טעינה מחדש של הרישום — התוסף הפתוח נשאר על המסך (הבאג המקורי)', () {
      final loaded = PluginSystemLoaded([_plugin(storeId)]);
      final available = resolveToolLookup(_lookup(storeId, loaded), null);
      final entry = (available as ToolAvailable).entry;

      // רגע ה-LoadPlugins: ה-Bloc אינו ב-Loaded, אבל התוסף כבר מוצג.
      final resolved = resolveToolLookup(
        _lookup(storeId, PluginSystemLoading()),
        entry,
      );

      expect(resolved, isA<ToolAvailable>());
      expect((resolved as ToolAvailable).entry.plugin?.pluginId, storeId);
    });

    test('דיאלוג ההרשאות של התקנה — גם הוא אינו מפרק את התוסף', () {
      final loaded = PluginSystemLoaded([_plugin(storeId)]);
      final entry =
          (resolveToolLookup(_lookup(storeId, loaded), null) as ToolAvailable)
              .entry;

      final installing = PluginSystemInstallRequiresPermissions(
        manifest: _plugin('other.plugin').manifest,
        tempDirPath: '/tmp/other',
      );

      expect(
        resolveToolLookup(_lookup(storeId, installing), entry),
        isA<ToolAvailable>(),
      );
    });

    test('התוסף הוסר — המצב האמיתי גובר על הכלי הקודם', () {
      final loaded = PluginSystemLoaded([_plugin(storeId)]);
      final entry =
          (resolveToolLookup(_lookup(storeId, loaded), null) as ToolAvailable)
              .entry;

      final resolved = resolveToolLookup(
        _lookup(storeId, const PluginSystemLoaded([])),
        entry,
      );

      expect(
        resolved,
        isA<ToolUnavailable>().having(
          (u) => u.reason,
          'reason',
          ToolUnavailableReason.notFound,
        ),
      );
    });
  });
}
