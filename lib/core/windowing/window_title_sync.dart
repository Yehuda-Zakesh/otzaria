import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// מעדכן את כותרת החלון לפי הכרטיסיה הפעילה בו, כמו בדפדפן.
///
/// ## למה זה נדרש דווקא עכשיו
///
/// לאוצריא יש סרגל כותרת מותאם (`setTitleBarStyle(hidden)`), ולכן הכותרת
/// של החלון אינה נראית **בחלון עצמו** — היא נראית בשורת המשימות, ב-Alt+Tab,
/// בתצוגות המקדימות של מחליף החלונות, ובמנהל המשימות.
///
/// בחלון יחיד לא היה בזה עניין. עם ארבעה חלונות, כולם בשם `אוצריא`, המשתמש
/// מקבל ארבעה כפתורים זהים בשורת המשימות ואין לו דרך לדעת מה בכל אחד — וזו
/// בדיוק הבעיה שדפדפנים פתרו בכך שהכותרת עוקבת אחרי הטאב הפעיל.
///
/// ## החוזה מול T-1.6
///
/// ⚠️ **מרגע זה הכותרת אינה מזהה יציב.** `main.cpp` מזהה את החלון הראשי
/// דרך מאפיין חלון (`OtzariaMainWindow`) ולא דרך הכותרת, בדיוק מהסיבה הזו.
/// הנפילה-לאחור ל-`FindWindowW` לפי כותרת נשארה שם עבור מופע שרץ מבנייה
/// קודמת, והיא best-effort — אין להישען עליה.
class WindowTitleSync {
  WindowTitleSync._();

  /// שם התוכנה, שנשאר בסוף הכותרת בכל מצב.
  ///
  /// מיקום בסוף ולא בהתחלה: שורת המשימות ו-Alt+Tab חותכים כותרות ארוכות
  /// **מהסוף**, ולכן מה שמזהה את החלון חייב לבוא ראשון.
  static const String appName = 'אוצריא';

  static bool get _isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// הכותרת שנשלחה לאחרונה — מונע קריאת ערוץ בכל שינוי state.
  static String? _lastSent;

  /// בונה את הכותרת לכרטיסיה הפעילה.
  ///
  /// [activeTabTitle] הוא null כשאין כרטיסיות או כשהמשתמש במסך אחר.
  @visibleForTesting
  static String titleFor(String? activeTabTitle, {int tabCount = 0}) {
    final trimmed = activeTabTitle?.trim();
    if (trimmed == null || trimmed.isEmpty) return appName;
    // מספר הכרטיסיות בסוגריים כמו בדפדפן, ורק כשיש יותר מאחת — בכרטיסיה
    // בודדת זה רק רעש.
    final suffix = tabCount > 1 ? ' ($tabCount)' : '';
    return '$trimmed$suffix — $appName';
  }

  /// מעדכן את כותרת החלון, אם היא שונה מזו שנשלחה.
  static Future<void> update(String? activeTabTitle, {int tabCount = 0}) async {
    if (!_isSupported) return;
    final title = titleFor(activeTabTitle, tabCount: tabCount);
    if (title == _lastSent) return;
    _lastSent = title;
    try {
      await windowManager.setTitle(title);
    } catch (e) {
      // כותרת אינה שווה קריסה, ואינה שווה גם הודעה למשתמש.
      debugPrint('setTitle failed: $e');
    }
  }
}
