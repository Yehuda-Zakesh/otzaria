import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';

/// חיווי התקדמות על אייקון ה-Dock של מק — המקום שבו משתמשי מק מצפים לראות
/// עבודה שרצה ברקע בזמן שהחלון מוסתר.
///
/// בפלטפורמות אחרות אינו עושה דבר.
class DockProgress {
  DockProgress._();

  /// הערכים ש-`setProgressBar` מפרש כ"הסתר" וכ"בלתי-מוגדר".
  static const double _hidden = -1;
  static const double _indeterminate = 2;

  static AppWindowGeometry _geometry = const WindowManagerAppWindowController();

  /// אחרון שנשלח — מונע קריאת ערוץ בכל ספר שנסרק.
  static double? _lastSent;

  /// עוקף את זיהוי הפלטפורמה — כדי שהבדיקות ירוצו גם מחוץ למק.
  @visibleForTesting
  static bool? debugIsSupportedOverride;

  /// הדוק שייך לתהליך, וחלון משני שידווח עליו יתנגש עם הראשי.
  static bool get isSupported =>
      debugIsSupportedOverride ??
      (!kIsWeb && Platform.isMacOS && ProcessDuties.current.isProcessOwner);

  /// מציג התקדמות [value] בין 0 ל-1, או חיווי בלתי-מוגדר כש-[value] הוא `null`.
  static Future<void> show({double? value}) =>
      _send(value == null ? _indeterminate : value.clamp(0.0, 1.0));

  /// מסיר את החיווי מאייקון ה-Dock.
  static Future<void> hide() => _send(_hidden);

  static Future<void> _send(double progress) async {
    if (!isSupported) return;
    // עיגול לאחוז: שינוי דק מזה אינו נראה על אייקון בגודל דוק.
    final rounded = progress < 0 || progress > 1
        ? progress
        : (progress * 100).roundToDouble() / 100;
    if (_lastSent == rounded) return;
    _lastSent = rounded;
    try {
      await _geometry.setProgressBar(rounded);
    } catch (e) {
      debugPrint('DockProgress: setProgressBar failed: $e');
    }
  }

  @visibleForTesting
  static void setGeometryForTesting(AppWindowGeometry geometry) {
    _geometry = geometry;
    _lastSent = null;
  }

  @visibleForTesting
  static void resetForTesting() {
    _geometry = const WindowManagerAppWindowController();
    _lastSent = null;
    debugIsSupportedOverride = null;
  }
}
