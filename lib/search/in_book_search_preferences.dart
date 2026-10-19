import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/settings/engine/app_settings_store.dart';

/// העדפת "מילים שלמות בלבד" של החיפוש בתוך ספר (טקסט ו-PDF).
///
/// כבוי כברירת מחדל: הקלדת "שמים" מוצאת גם "השמים", כמו Ctrl+F בכל תוכנה.
class InBookSearchPreferences {
  static const String _wholeWordKey = 'key-in-book-search-whole-word';

  InBookSearchPreferences._();

  static bool loadWholeWord() {
    try {
      return Settings.getValue<bool>(_wholeWordKey) ?? false;
    } catch (e) {
      // Settings שלא אותחל (בדיקות, עלייה מוקדמת) — ברירת המחדל.
      debugPrint('טעינת העדפת מילים שלמות נכשלה: $e');
      return false;
    }
  }

  /// האם ההתאמה בספר תהיה של מילים שלמות, בהינתן המסלול שירוץ בפועל.
  /// מסלול המנוע תמיד מילים שלמות — ההדגשה שם נגזרת מהתבנית שהמנוע בנה
  /// ואינה מושפעת מהמתג.
  static bool resolveWholeWord({required bool isSimpleSearch}) =>
      isSimpleSearch ? loadWholeWord() : true;

  static Future<void> saveWholeWord(bool value) async {
    try {
      await Settings.setValue<bool>(_wholeWordKey, value);
    } catch (e) {
      debugPrint('שמירת העדפת מילים שלמות נכשלה: $e');
    }
  }
}
