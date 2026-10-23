import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/last_active_window.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

/// ה-GlobalKey-ים שיש מהם אחד בכל חלון, כדי שחלונות ב-isolate משותף לא יתנגשו.
/// נוצר מעל `RestartWidget` וחי כחלון, כך שה-State עובר הפעלה מחדש כמו קודם.
/// מפתחות של מסכי האפליקציה מוגדרים כ-extension ליד ה-widget שלהם, כדי שהקובץ
/// הזה לא ימשוך את כל גרף היבוא.
class AppWindowKeys {
  AppWindowKeys({this.id = AppWindowId.primary});

  /// החלון שהמפתחות שייכים לו; לפיו [activateWindow] מוצא אותם.
  final AppWindowId id;

  /// ה-Navigator של ה-MaterialApp. דרכו מוצגים דיאלוגים והודעות.
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  final GlobalKey enhancedSearchField = GlobalKey();

  /// גבול הציור של אזור התוכן. ⚠️ ה-[RepaintBoundary] שלו אינו רק לצילום:
  /// הוא מבודד את הצטיירות התוכן הכבד מסרגל הכרטיסיות שמעליו.
  final GlobalKey windowContentBoundary = GlobalKey();

  /// יעדי הסיור המודרך.
  final TourTargetKeys tour = TourTargetKeys();

  static final AppWindowKeys _primary = AppWindowKeys();
  static AppWindowKeys _current = _primary;
  static final Map<AppWindowId, AppWindowKeys> _windows = {
    AppWindowId.primary: _primary,
  };

  /// החלון הפעיל האחרון ([activateWindow]), למי שאין לו `BuildContext`.
  /// widget או bloc משתמשים ב-[of], כדי שבנייה בחלון ברקע לא תפנה לחלון שבפוקוס.
  static AppWindowKeys get current => _current;

  static void activate(AppWindowKeys keys) => _current = keys;

  /// המפתחות של החלון [id], אם הוא רשום.
  static AppWindowKeys? byId(AppWindowId id) => _windows[id];

  /// כל החלונות הרשומים, כולל הראשי.
  static Iterable<AppWindowKeys> get registered => _windows.values;

  /// רושם חלון כדי ש-[activateWindow] יוכל להפעיל אותו (שלב 1: יצירת חלון).
  static void register(AppWindowKeys keys) => _windows[keys.id] = keys;

  /// מבטל רישום; אם זה היה החלון הנוכחי, עובר לחלון רשום אחר.
  static void unregister(AppWindowKeys keys) {
    if (!identical(_windows[keys.id], keys)) return;
    _windows.remove(keys.id);
    if (identical(_current, keys) && _windows.isNotEmpty) {
      _current = _windows[AppWindowId.primary] ?? _windows.values.first;
    }
  }

  /// החלון [id] קיבל פוקוס: מסומן כפעיל אחרון, ואם הוא רשום — הופך ל-[current].
  static void activateWindow(AppWindowId id) {
    LastActiveWindow.markActive(id);
    final keys = _windows[id];
    if (keys != null) _current = keys;
  }

  /// מחזיר את הרישום ואת [current] לחלון הראשי — לבדיקות בלבד.
  @visibleForTesting
  static void resetForTest() {
    _windows
      ..clear()
      ..[AppWindowId.primary] = _primary;
    _current = _primary;
  }

  /// האם [context] יושב בחלון הפעיל. `HardwareKeyboard` מעביר מקשים מכל
  /// החלונות לכל המאזינים, ולכן מאזין גלובלי פועל רק כשזה נכון.
  static bool isActiveWindow(BuildContext context) =>
      identical(of(context), _current);

  /// מפתחות החלון ש-[context] יושב בו, או [current] אם אין scope מעליו.
  /// בלי רישום תלות: המפתחות קבועים לחיי החלון, וכך מותר לקרוא גם מ-callback.
  static AppWindowKeys of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppWindowScope>()?.keys ?? _current;
}
