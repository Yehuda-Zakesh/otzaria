import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/settings/engine/app_settings_store.dart';

/// זיכרון הבחירה האחרונה בשורות החיפוש הסטטיות של תוספים.
///
/// המפתח הוא `<pluginId>/<itemId>`, וערך שמור גובר על `defaultValue` שבמניפסט.
class PluginSearchSelectionPreferences {
  static const String _key = 'key-plugin-search-selections';

  PluginSearchSelectionPreferences._();

  static Map<String, bool> load() {
    final String? raw;
    try {
      raw = Settings.getValue<String>(_key);
    } catch (e) {
      // Settings לא אותחל (בדיקות ווידג'ט / אתחול מוקדם) — אין העדפות.
      debugPrint('[PluginSearchSelections] settings unavailable: $e');
      return const {};
    }
    if (raw == null || raw.trim().isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is bool)
            entry.key as String: entry.value as bool,
      };
    } catch (e) {
      debugPrint('[PluginSearchSelections] JSON parse failed: $e');
      return const {};
    }
  }

  static Future<void> save(Map<String, bool> selections) async {
    try {
      await Settings.setValue<String>(_key, jsonEncode(selections));
    } catch (e) {
      debugPrint(
        '[PluginSearchSelections] settings unavailable, not saved: $e',
      );
    }
  }
}
