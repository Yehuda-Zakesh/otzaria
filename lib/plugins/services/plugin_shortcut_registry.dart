import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_shortcut.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

/// רישום קיצורי המקלדת שתוספים מצהירים עליהם — מהמניפסט
/// (`contributes.startup.shortcuts`) או בזמן ריצה (`app.registerShortcut`).
///
/// כל קיצור חייב לקשר לפחות לאחת משתי הפעולות: [PluginShortcut.command]
/// (פקודה חופשית שנשלחת באירוע `app.command`) או
/// [PluginShortcut.contextMenuItemId] (פעולת תפריט הלחיצה הימנית).
///
/// הרשמה ל-ChangeNotifier מאפשרת למסך הגדרות קיצורי המקשים ולמטפל המקלדת
/// להישאר מעודכנים כשקיצור נוסף/מוסר/מתעדכן בזמן ריצה.
class PluginShortcutRegistry extends ChangeNotifier {
  static const int maxShortcutsPerPlugin = 32;
  static final PluginShortcutRegistry instance = PluginShortcutRegistry._();
  PluginShortcutRegistry._();

  @visibleForTesting
  PluginShortcutRegistry.forTesting();

  final Map<String, Map<String, PluginShortcut>> _byPlugin = {};

  /// רושם קיצור [shortcut] עבור [pluginId]. קיצור קיים עם אותו [id] מוחלף.
  /// זורק [PluginShortcutException] אם לקיצור אין גם [command] וגם
  /// [contextMenuItemId] — קיצור כזה לא היה מפעיל דבר.
  void register(String pluginId, PluginShortcut shortcut) {
    final normalized = _validate(pluginId, shortcut);
    final shortcuts = _byPlugin.putIfAbsent(pluginId, () => {});
    if (!shortcuts.containsKey(normalized.id) &&
        shortcuts.length >= maxShortcutsPerPlugin) {
      throw const PluginShortcutException(
        'error.invalid_params',
        'a plugin can register at most 32 keyboard shortcuts',
      );
    }
    shortcuts[normalized.id] = normalized;
    notifyListeners();
  }

  /// רושם קיצור מ-payload גולמי (RPC / מניפסט). מחזיר את הקיצור המפוענח.
  PluginShortcut registerPayload(
    String pluginId,
    Map<String, dynamic> payload,
  ) {
    final shortcut = PluginShortcut.fromJson(payload);
    register(pluginId, shortcut);
    return _byPlugin[pluginId]![shortcut.id]!;
  }

  /// מעדכן את [id] של קיצור לפי [patch] (נכון לעכשיו רק `key` נתמך).
  PluginShortcut update(
    String pluginId,
    String id,
    Map<String, dynamic> patch,
  ) {
    final current = _byPlugin[pluginId]?[id];
    if (current == null) {
      throw const PluginShortcutException(
        'error.not_found',
        'keyboard shortcut was not found',
      );
    }
    final key = patch['key'];
    if (patch.length != 1 || key is! String) {
      throw const PluginShortcutException(
        'error.invalid_params',
        'patch must contain only a string key',
      );
    }
    final updated = _validate(pluginId, current.copyWith(key: key));
    _byPlugin[pluginId]![id] = updated;
    notifyListeners();
    return updated;
  }

  void remove(String pluginId, String id) {
    final list = _byPlugin[pluginId];
    final removed = list?.remove(id);
    if (list?.isEmpty == true) _byPlugin.remove(pluginId);
    if (removed != null) notifyListeners();
  }

  bool hasPlugin(String pluginId) => _byPlugin[pluginId]?.isNotEmpty ?? false;

  void removeAll(String pluginId) {
    if (_byPlugin.remove(pluginId) != null) notifyListeners();
  }

  List<(String pluginId, PluginShortcut shortcut)> getAll() {
    return List.unmodifiable([
      for (final entry in _byPlugin.entries)
        for (final shortcut in entry.value.values) (entry.key, shortcut),
    ]);
  }

  PluginShortcut? find(String pluginId, String id) => _byPlugin[pluginId]?[id];

  PluginShortcut _validate(String pluginId, PluginShortcut shortcut) {
    if (shortcut.id.isEmpty || shortcut.label.isEmpty) {
      throw const PluginShortcutException(
        'error.invalid_params',
        'shortcut requires id and label',
      );
    }
    if (shortcut.command == null && shortcut.contextMenuItemId == null) {
      throw const PluginShortcutException(
        'error.invalid_params',
        'shortcut requires command or contextMenuItemId',
      );
    }
    final normalizedKey = ShortcutHelper.normalizeShortcut(shortcut.key);
    if (normalizedKey == null) {
      throw const PluginShortcutException(
        'error.invalid_params',
        'shortcut key is not recognized',
      );
    }
    return shortcut.copyWith(key: normalizedKey);
  }
}

class PluginShortcutException implements Exception {
  final String code;
  final String message;

  const PluginShortcutException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}
