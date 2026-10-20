import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

/// מה החלון מציג: מסך, כרטיסייה נוכחית, ספירה לפי סוג ותוספים גלויים.
/// משמש את רשומות ה-context של אבחון המפתחים ואת הדיווח על התוכנה.
Map<String, Object?> describeAppContext({
  required Screen screen,
  required TabsState tabs,
  required PluginSystemState pluginState,
}) {
  final current = tabs.currentTab;
  final tabsByType = <String, int>{};
  for (final tab in tabs.tabs) {
    tabsByType.update(
      tab.runtimeType.toString(),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return {
    'screen': screen.name,
    'tabs': tabs.tabs.length,
    'tabsByType': tabsByType,
    'currentTab': current?.runtimeType.toString(),
    'currentTitle': current == null || leafPanes(current).any(_isPrivateTitle)
        ? null
        : current.title,
    'plugins': [
      for (final id in {
        for (final key in ToolTab.visiblePluginInstancesOf(current))
          key.pluginId,
      })
        _pluginContext(id, pluginState),
    ],
  };
}

/// כותרת חיפוש היא השאילתה, וכותרת ספר אישי היא לרוב שם הקובץ.
bool _isPrivateTitle(OpenedTab pane) =>
    pane is SearchingTab ||
    (pane is CommentatorsTab && _isPrivateTitle(pane.sourceTab)) ||
    (pane is PdfCommentatorsTab && _isPrivateTitle(pane.sourceTab)) ||
    (pane is PdfBookTab && pane.book.isUserBook) ||
    (pane is TextBookTab && pane.book.isUserBook);

Map<String, Object?> _pluginContext(String pluginId, PluginSystemState state) {
  final plugins = state is PluginSystemLoaded
      ? state.plugins
      : const <InstalledPlugin>[];
  for (final plugin in plugins) {
    if (plugin.pluginId != pluginId) continue;
    return {
      'id': pluginId,
      'version': plugin.version,
      'source': plugin.sourceType,
      'enabled': plugin.enabled,
    };
  }
  return {'id': pluginId};
}
