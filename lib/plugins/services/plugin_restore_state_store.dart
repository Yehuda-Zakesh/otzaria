import 'dart:collection';
import 'dart:convert';

import 'package:otzaria/plugins/plugin_constants.dart';

/// למה דף של מופע קיים נטען מחדש — נמסר לתוסף ב-`plugin.boot.restore.reason`.
enum PluginRestoreReason { discarded, crashed, reloaded, session }

/// מצב השחזור שתוסף שמר דרך `plugin.setRestoreState`, לפי מופע.
///
/// המצב של טאב כלי נשמר גם עם ה-JSON של הטאב (סשן וסביבות עבודה).
/// טאבים שנזרעו משולחן עבודה או מעותק לא תמיד משתחררים, ולכן הזיכרון חסום:
/// מעבר ל-[maxEntries] או ל-[maxTotalBytes] נמחק מה שעודכן לפני הכול.
class PluginRestoreStateStore {
  PluginRestoreStateStore._();
  static final PluginRestoreStateStore instance = PluginRestoreStateStore._();

  /// גבול לגודל המצב אחרי קידוד, בבתים של UTF-8.
  static const int maxStateBytes = 64 * 1024;
  static const int maxEntries = 64;
  static const int maxTotalBytes = 2 * 1024 * 1024;

  /// לפי סדר העדכון האחרון — הראשון הוא הוותיק.
  final LinkedHashMap<PluginInstanceKey, ({String json, int bytes})> _states =
      LinkedHashMap();
  int _totalBytes = 0;

  int get length => _states.length;
  int get totalBytes => _totalBytes;

  /// שומר את [state] (כל ערך JSON) עבור [key]; `null` מוחק.
  ///
  /// זורק [ArgumentError] כשהערך אינו ניתן לקידוד או גדול מ-[maxStateBytes].
  void set(PluginInstanceKey key, Object? state) {
    if (state == null) {
      remove(key);
      return;
    }
    final String encoded;
    try {
      encoded = jsonEncode(state);
    } on JsonUnsupportedObjectError {
      throw ArgumentError('state must be JSON-serializable');
    }
    final bytes = utf8.encode(encoded).length;
    if (bytes > maxStateBytes) {
      throw ArgumentError('state exceeds $maxStateBytes bytes');
    }
    _put(key, encoded, bytes);
  }

  /// המצב המקודד כפי שנשמר, או `null`.
  String? jsonOf(PluginInstanceKey key) => _states[key]?.json;

  /// זורע מצב מקודד שנטען מסשן שמור. מצב פגום או גדול מדי נזרק.
  void seed(PluginInstanceKey key, String json) {
    final bytes = utf8.encode(json).length;
    if (bytes > maxStateBytes) return;
    try {
      jsonDecode(json);
    } on FormatException {
      return;
    }
    _put(key, json, bytes);
  }

  void _put(PluginInstanceKey key, String json, int bytes) {
    remove(key);
    _states[key] = (json: json, bytes: bytes);
    _totalBytes += bytes;
    while (_states.length > maxEntries || _totalBytes > maxTotalBytes) {
      remove(_states.keys.first);
    }
  }

  bool has(PluginInstanceKey key) => _states.containsKey(key);

  Object? stateOf(PluginInstanceKey key) {
    final json = _states[key]?.json;
    return json == null ? null : jsonDecode(json);
  }

  void remove(PluginInstanceKey key) {
    final removed = _states.remove(key);
    if (removed != null) _totalBytes -= removed.bytes;
  }

  /// מסיר את המצב של מופע לפי המזהה בלבד — כשהתוסף כבר אינו ידוע.
  void removeInstanceId(String instanceId) {
    for (final key in _states.keys.toList()) {
      if (key.instanceId == instanceId) remove(key);
    }
  }
}
