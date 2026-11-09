import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_text.dart';

/// ניקוד וטעמים בלבד (U+0591–U+05C7). מקף, פסק, סוף פסוק ונון הפוכה הם
/// סימני פיסוק ונשארים בטקסט, כדי שהעורך לא ישנה אותם.
bool isPluginCorrectionNikudMark(int c) =>
    (c >= 0x0591 && c <= 0x05BD) ||
    c == 0x05BF ||
    c == 0x05C1 ||
    c == 0x05C2 ||
    c == 0x05C4 ||
    c == 0x05C5 ||
    c == 0x05C7;

/// בקר טקסט פשוט שמסתיר רק את הרווחים שנוצרו מתגיות בלוק בקצוות.
///
/// כשהספר מוגדר ללא ניקוד ([hideNikud]) העורך מציג את הטקסט בלי ניקוד, אבל
/// הניקוד נשמר במקור: [forService] ממפה כל עריכה בחזרה לנוסח המנוקד, כך
/// שאותיות שלא נגעו בהן שומרות את הניקוד שלהן ורק הטקסט שהוקלד נכנס בלעדיו.
class PluginCorrectionController extends TextEditingController {
  late PluginCorrectionText source;
  String? _sourceText;
  String _prefix = '';
  String _suffix = '';
  bool hideNikud;

  /// הטקסט הגלוי כולל ניקוד, כפי שהוא במצב האחרון שהעורך סונכרן אליו.
  String _base = '';

  PluginCorrectionController(String raw, {this.hideNikud = false}) {
    setSource(raw);
  }

  void setSource(String raw) {
    if (_sourceText == raw) return;
    source = PluginCorrectionText(raw);
    _sourceText = raw;
    value = TextEditingValue(text: forEditor(source.plain));
  }

  String forEditor(String canonical) {
    final visible = _visibleOf(canonical);
    _base = visible;
    return hideNikud ? stripNikud(visible) : visible;
  }

  /// הטקסט בעורך כבר שווה ל-[canonical] (כולל רווחים שהוקלדו בשוליים): רק
  /// מעדכנים את בסיס הניקוד, בלי לגעת בעורך או בשוליים.
  void adopt(String canonical) {
    final end = canonical.length - _suffix.length;
    _base =
        canonical.startsWith(_prefix) &&
            canonical.endsWith(_suffix) &&
            end >= _prefix.length
        ? canonical.substring(_prefix.length, end)
        : canonical;
  }

  String _visibleOf(String canonical) {
    final prefix = source.plain.substring(0, source.visibleStart);
    final suffix = source.plain.substring(source.visibleEnd);
    _prefix = '';
    _suffix = '';
    if (!canonical.startsWith(prefix) ||
        !canonical.endsWith(suffix) ||
        canonical.length < prefix.length + suffix.length) {
      return canonical;
    }
    _prefix = prefix;
    _suffix = suffix;
    return canonical.substring(prefix.length, canonical.length - suffix.length);
  }

  /// פונקציה טהורה: אינה משנה מצב, ולכן בטוחה לבדיקות ואימות לפני החלה.
  String forService(String visible) =>
      _prefix +
      (hideNikud ? mergeIntoNikud(_base, visible) : visible) +
      _suffix;

  static String stripNikud(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (!isPluginCorrectionNikudMark(c)) out.writeCharCode(c);
    }
    return out.toString();
  }

  /// מחיל על [base] (מנוקד) את ההבדל בין [base] ללא ניקוד לבין [visible].
  /// הטווח שהשתנה מוחלף בלבד; ניקוד של אותיות שלא השתנו נשמר.
  static String mergeIntoNikud(String base, String visible) {
    // ניקוד שהוקלד או הודבק בזמן שהספר מוסתר ללא ניקוד אינו נכנס למקור: אחרת
    // היה מוכפל על הניקוד הקיים ומשבש עריכות הבאות.
    visible = stripNikud(visible);
    final map = <int>[];
    final stripped = StringBuffer();
    for (var i = 0; i < base.length; i++) {
      final c = base.codeUnitAt(i);
      if (isPluginCorrectionNikudMark(c)) continue;
      map.add(i);
      stripped.writeCharCode(c);
    }
    final plain = stripped.toString();
    if (plain == visible) return base;
    var prefix = 0;
    while (prefix < plain.length &&
        prefix < visible.length &&
        plain.codeUnitAt(prefix) == visible.codeUnitAt(prefix)) {
      prefix++;
    }
    // לא חותכים באמצע זוג surrogate.
    if (prefix > 0 &&
        prefix < plain.length &&
        _isHighSurrogate(plain.codeUnitAt(prefix - 1))) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < plain.length - prefix &&
        suffix < visible.length - prefix &&
        plain.codeUnitAt(plain.length - 1 - suffix) ==
            visible.codeUnitAt(visible.length - 1 - suffix)) {
      suffix++;
    }
    if (suffix > 0 &&
        _isLowSurrogate(plain.codeUnitAt(plain.length - suffix))) {
      suffix--;
    }
    final start = prefix < plain.length ? map[prefix] : base.length;
    final end = suffix == 0 ? base.length : map[plain.length - suffix];
    return base.substring(0, start) +
        visible.substring(prefix, visible.length - suffix) +
        base.substring(end);
  }

  static bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;
  static bool _isLowSurrogate(int c) => c >= 0xDC00 && c <= 0xDFFF;
}
