import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

/// רשומת תצוגה מאוחדת לכלי מובנה או לתוסף.
class ToolCatalogEntry {
  final String toolId;
  final String label;
  final int order;

  /// אייקון Fluent. `null` רק כאשר [imageIcon] קיים.
  final IconData? icon;
  final IconData? iconFilled;

  /// נכס תמונה, לכלים שמשתמשים בלוגו במקום באייקון (כמו "שמור וזכור").
  final String? imageIcon;

  final InstalledPlugin? plugin;

  const ToolCatalogEntry({
    required this.toolId,
    required this.label,
    required this.order,
    this.icon,
    this.iconFilled,
    this.imageIcon,
    this.plugin,
  });

  bool get isPlugin => plugin != null;
  bool get isDevelopment => plugin?.isDevelopment ?? false;

  /// [order] דוחק את סדר הקטלוג — משמש כשהמשתמש קבע סדר משלו לכלים המובנים.
  factory ToolCatalogEntry.fromBuiltIn(BuiltInToolMeta meta, {int? order}) =>
      ToolCatalogEntry(
        toolId: meta.toolId,
        label: meta.label,
        order: order ?? meta.order,
        icon: meta.icon,
        iconFilled: meta.iconFilled,
        imageIcon: meta.imageIcon,
      );

  factory ToolCatalogEntry.fromPlugin(InstalledPlugin plugin) {
    final icon =
        pluginIconFromName(plugin.manifest.toolTabIconName) ??
        FluentIcons.puzzle_piece_24_regular;
    return ToolCatalogEntry(
      toolId: plugin.pluginId,
      label: plugin.manifest.toolTabTitle,
      order: plugin.effectiveToolTabOrder,
      icon: icon,
      iconFilled: icon,
      plugin: plugin,
    );
  }

  /// קבוצת המיון: כלים מובנים תמיד לפני תוספים.
  int get sortGroupPriority => isPlugin ? 1 : 0;
}

/// ממיין רשומות לפי קבוצה וסדר תוך שמירת סדרן היחסי של רשומות זהות.
@visibleForTesting
void sortToolEntriesStably(List<ToolCatalogEntry> entries) {
  insertionSort(
    entries,
    compare: (a, b) {
      final byKind = a.sortGroupPriority.compareTo(b.sortGroupPriority);
      if (byKind != 0) return byKind;
      return a.order.compareTo(b.order);
    },
  );
}

/// אייקון קטן לשורת הכרטיסיות.
Widget? buildToolTabLeadingIcon(
  String toolId, {
  required Color color,
  double size = 14,
  PluginSystemState? pluginState,
}) {
  final builtIn = kBuiltInToolsCatalog.firstWhereOrNull(
    (meta) => meta.toolId == toolId,
  );
  if (builtIn != null) {
    if (builtIn.imageIcon != null) {
      return ImageIcon(
        AssetImage(builtIn.imageIcon!),
        size: size,
        color: color,
      );
    }
    return Icon(builtIn.icon, size: size, color: color);
  }

  IconData? icon;
  if (pluginState is PluginSystemLoaded) {
    final plugin = pluginState.plugins.firstWhereOrNull(
      (p) => p.pluginId == toolId,
    );
    if (plugin != null) {
      icon = pluginIconFromName(plugin.manifest.toolTabIconName);
    }
  }
  return Icon(
    icon ?? FluentIcons.puzzle_piece_24_regular,
    size: size,
    color: color,
  );
}

/// סיבת אי-זמינות של כלי לפתיחה.
enum ToolUnavailableReason {
  /// עדיין לא ידוע — `PluginSystemBloc` טרם סיים לטעון.
  loading,
  notFound,
  builtInHidden,
  pluginDisabled,
  pluginRequiresInternet,

  /// תוסף ללא ממשק — פועל ברקע בלבד ואין לו כרטיסייה.
  pluginHeadless,
}

/// תוצאת חיפוש כלי לפי מזהה: הרשומה עצמה, או הסיבה שאינה זמינה.
sealed class ToolLookupResult {
  const ToolLookupResult();
}

class ToolAvailable extends ToolLookupResult {
  final ToolCatalogEntry entry;
  const ToolAvailable(this.entry);
}

class ToolUnavailable extends ToolLookupResult {
  final ToolUnavailableReason reason;

  /// שם הכלי לתצוגה בהודעה, כשהוא ידוע.
  final String? name;
  const ToolUnavailable(this.reason, {this.name});
}

/// הכלים הזמינים להצגה במשגר.
///
/// [builtInToolsOrder] הוא סדר הכלים המובנים שהמשתמש קבע; ריק = סדר הקטלוג.
List<ToolCatalogEntry> buildToolCatalog({
  required Set<String> hiddenBuiltInToolIds,
  required bool isOfflineMode,
  required PluginSystemState pluginState,
  List<String> builtInToolsOrder = const [],
}) {
  final orderedBuiltIns = orderedBuiltInTools(builtInToolsOrder);
  final entries = <ToolCatalogEntry>[
    for (var i = 0; i < orderedBuiltIns.length; i++)
      if (!hiddenBuiltInToolIds.contains(orderedBuiltIns[i].toolId))
        ToolCatalogEntry.fromBuiltIn(orderedBuiltIns[i], order: i),
  ];

  if (pluginState is PluginSystemLoaded) {
    for (final plugin in pluginState.plugins) {
      if (!plugin.enabled) continue;
      if (!plugin.showInTools || !plugin.hasToolPage) continue;
      if (isOfflineMode && plugin.blockedInOfflineMode) continue;
      entries.add(ToolCatalogEntry.fromPlugin(plugin));
    }
  }

  sortToolEntriesStably(entries);
  return entries;
}

/// מאתר כלי לפי מזהה ומחזיר סיבה מפורטת אם אינו זמין.
ToolLookupResult lookupTool(
  String toolId, {
  required Set<String> hiddenBuiltInToolIds,
  required bool isOfflineMode,
  required PluginSystemState pluginState,
}) {
  final builtIn = kBuiltInToolsCatalog.firstWhereOrNull(
    (meta) => meta.toolId == toolId,
  );
  if (builtIn != null) {
    if (hiddenBuiltInToolIds.contains(toolId)) {
      return ToolUnavailable(
        ToolUnavailableReason.builtInHidden,
        name: builtIn.label,
      );
    }
    return ToolAvailable(ToolCatalogEntry.fromBuiltIn(builtIn));
  }

  if (pluginState is! PluginSystemLoaded) {
    return const ToolUnavailable(ToolUnavailableReason.loading);
  }

  final plugin = pluginState.plugins.firstWhereOrNull(
    (p) => p.pluginId == toolId,
  );
  if (plugin == null) {
    return const ToolUnavailable(ToolUnavailableReason.notFound);
  }
  if (!plugin.enabled) {
    return ToolUnavailable(
      ToolUnavailableReason.pluginDisabled,
      name: plugin.name,
    );
  }
  if (isOfflineMode && plugin.blockedInOfflineMode) {
    return ToolUnavailable(
      ToolUnavailableReason.pluginRequiresInternet,
      name: plugin.name,
    );
  }
  if (!plugin.hasToolPage) {
    return ToolUnavailable(
      ToolUnavailableReason.pluginHeadless,
      name: plugin.name,
    );
  }
  return ToolAvailable(ToolCatalogEntry.fromPlugin(plugin));
}
