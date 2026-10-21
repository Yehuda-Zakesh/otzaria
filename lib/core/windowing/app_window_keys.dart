import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

/// ה-GlobalKey-ים שיש מהם אחד בכל חלון, כדי שחלונות ב-isolate משותף לא יתנגשו.
/// נוצר מעל `RestartWidget` וחי כחלון, כך שה-State עובר הפעלה מחדש כמו קודם.
/// מפתחות של מסכי האפליקציה מוגדרים כ-extension ליד ה-widget שלהם, כדי שהקובץ
/// הזה לא ימשוך את כל גרף היבוא.
class AppWindowKeys {
  AppWindowKeys();

  /// ה-Navigator של ה-MaterialApp. דרכו מוצגים דיאלוגים והודעות.
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  final GlobalKey enhancedSearchField = GlobalKey();

  /// גבול הציור של אזור התוכן. ⚠️ ה-[RepaintBoundary] שלו אינו רק לצילום:
  /// הוא מבודד את הצטיירות התוכן הכבד מסרגל הכרטיסיות שמעליו.
  final GlobalKey windowContentBoundary = GlobalKey();

  /// יעדי הסיור המודרך.
  final TourTargetKeys tour = TourTargetKeys();

  static AppWindowKeys _current = AppWindowKeys();

  /// החלון הנוכחי, למי שאין לו `BuildContext`. היום — המופע היחיד של ה-isolate;
  /// ב-isolate משותף [activate] יעביר אותו לחלון הפעיל האחרון.
  static AppWindowKeys get current => _current;

  static void activate(AppWindowKeys keys) => _current = keys;

  /// מפתחות החלון ש-[context] יושב בו, או [current] אם אין scope מעליו.
  /// בלי רישום תלות: המפתחות קבועים לחיי החלון, וכך מותר לקרוא גם מ-callback.
  static AppWindowKeys of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppWindowScope>()?.keys ?? _current;
}
