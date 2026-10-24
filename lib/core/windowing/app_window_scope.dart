import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/window_role.dart';

/// מספק לכל widget את החלון שהוא יושב בו.
///
/// `InheritedWidget` ולא `Provider`: עץ ה-providers ב-`main.dart` מונה כבר
/// כ-18 רשומות, ופרק 4 של מפת הדרכים מתכנן לפצל אותו לפי בעלות (host מול
/// פר-חלון). הוספת תלות חדשה לאותו עץ עכשיו רק תגדיל את מה שיצטרך להתפצל,
/// והזהות של החלון אינה משתנה בזמן ריצה ולכן אינה זקוקה למנגנון עשיר.
class AppWindowScope extends InheritedWidget {
  const AppWindowScope({
    super.key,
    required this.controller,
    required this.geometry,
    this.keys,
    this.role,
    required super.child,
  });

  final AppWindowController controller;
  final AppWindowGeometry geometry;

  /// ה-GlobalKey-ים של החלון; `null` — [AppWindowKeys.current]. נשלף דרך
  /// [AppWindowKeys.of].
  final AppWindowKeys? keys;

  /// תפקיד החלון; `null` — [AppWindowRole.main]. נשלף דרך [roleOf].
  final AppWindowRole? role;

  static AppWindowController controllerOf(BuildContext context) =>
      _of(context).controller;

  static AppWindowGeometry geometryOf(BuildContext context) =>
      _of(context).geometry;

  /// בלי scope מעל (בדיקות) — [AppWindowRole.main]. אינו רושם תלות:
  /// התפקיד קבוע לכל חיי החלון, ונקרא גם מתוך `create` של ספקים.
  static AppWindowRole roleOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppWindowScope>()?.role ??
      AppWindowRole.main;

  static AppWindowScope _of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppWindowScope>();
    assert(scope != null, 'AppWindowScope חסר מעל ה-widget הזה');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppWindowScope oldWidget) =>
      controller != oldWidget.controller ||
      geometry != oldWidget.geometry ||
      keys != oldWidget.keys ||
      role != oldWidget.role;
}
