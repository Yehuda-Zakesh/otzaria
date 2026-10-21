import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';

/// רישום שורות חיפוש סטטיות של תוספים.
///
/// הרישום מכיל הצהרות מניפסט בלבד, ולכן פתיחת דיאלוג החיפוש אינה מפעילה
/// WebView או שולחת אירוע לתוסף.
class PluginSearchDialogRegistry extends ChangeNotifier {
  static final PluginSearchDialogRegistry instance =
      PluginSearchDialogRegistry._();
  PluginSearchDialogRegistry._() {
    _attachEvaluator(PluginConditionEvaluator.instance);
  }

  @visibleForTesting
  PluginSearchDialogRegistry.forTesting({PluginConditionEvaluator? evaluator}) {
    if (evaluator != null) _attachEvaluator(evaluator);
  }

  PluginSearchDialogRegistry.detached();

  final Map<PluginInstanceKey, List<PluginSearchDialogItem>> _items = {};
  PluginConditionEvaluator? _evaluator;

  void _attachEvaluator(PluginConditionEvaluator evaluator) {
    _evaluator = evaluator;
    evaluator.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _evaluator?.removeListener(notifyListeners);
    super.dispose();
  }

  void registerPayload(
    String pluginId,
    Map<String, dynamic> payload, {
    String instanceId = PluginInstanceIds.pluginLevel,
  }) {
    final item = PluginSearchDialogItem.fromPayload(payload);
    final items = _items.putIfAbsent(
      (pluginId: pluginId, instanceId: instanceId),
      () => [],
    );
    final existing = items.indexWhere((candidate) => candidate.id == item.id);
    if (existing < 0 &&
        items.length >= PluginSearchDialogItem.maxItemsPerPlugin) {
      throw const PluginSearchDialogItemException(
        'a plugin can register at most 4 search dialog items',
      );
    }
    // הצהרת resultsProvider היא מניפסט-בלבד, ולכן הספק נרשם כבר בסנכרון
    // התוספים — טאב חיפוש משוחזר מפעיל את המדור מיד עם עליית האפליקציה,
    // בלי להמתין ל-boot של התוסף (המנוע מוּעָר בעת הבקשה הראשונה).
    if (item.resultsProvider != null && this == instance) {
      PluginExternalSearchService.instance.register(
        item.resultsProvider!,
        pluginId,
      );
    }
    if (existing >= 0) {
      items[existing] = item;
    } else {
      items.add(item);
    }
    notifyListeners();
  }

  void remove(
    String pluginId,
    String itemId, {
    String instanceId = PluginInstanceIds.pluginLevel,
  }) {
    final items = _items[(pluginId: pluginId, instanceId: instanceId)];
    if (items == null) return;
    final before = items.length;
    items.removeWhere((item) => item.id == itemId);
    _items.removeWhere((_, list) => list.isEmpty);
    if (items.length != before) notifyListeners();
  }

  /// ניקוי מלא ברמת התוסף — כל המופעים והרישומים הדקלרטיביים.
  void removeAll(String pluginId) {
    final before = _items.length;
    _items.removeWhere((key, _) => key.pluginId == pluginId);
    if (_items.length != before) notifyListeners();
  }

  /// השורות המוצגות בפועל — שורה שתנאי ה-`when` שלה אינו מתקיים מסוננת החוצה
  /// (ונשארת רשומה, כך שהיא חוזרת כשהתנאי מתקיים). שורה זהה שנרשמה מכמה
  /// מופעים מוצגת פעם אחת.
  List<(String pluginId, PluginSearchDialogItem item)> getAll() {
    final deduped = <(String, String), (String, PluginSearchDialogItem)>{};
    for (final entry in _items.entries) {
      final pluginId = entry.key.pluginId;
      for (final item in entry.value) {
        if (!(_evaluator?.isVisible(pluginId, item.when) ?? true)) continue;
        final dedupeKey = (pluginId, item.id);
        if (!deduped.containsKey(dedupeKey) ||
            entry.key.instanceId != PluginInstanceIds.pluginLevel) {
          deduped[dedupeKey] = (pluginId, item);
        }
      }
    }
    return List.unmodifiable(deduped.values);
  }
}
