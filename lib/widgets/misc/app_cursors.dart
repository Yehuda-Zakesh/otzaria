import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// סמני אחיזה/גרירה משותפים (דפדוף בתצוגת ספר, סידור תוספים וכד').
///
/// ב-Windows אין grab/grabbing במנוע (flutter#99323), לכן נוצר שם סמן
/// מותאם מאייקון Fluent; בשאר הפלטפורמות משתמשים בסמני המערכת.
class AppCursors {
  AppCursors._();

  /// יד פתוחה — ריחוף על אזור אחיז. ב-Windows הסמן נבנה ל-DPR של התצוגה
  /// הראשונה; [grabOf] בונה אותו לתצוגה של הווידג'ט.
  static MouseCursor get grab => _grab(null);

  /// בזמן גרירה פעילה (ב-Windows זהה ל-[grab] — אין גליף אגרוף ב-Fluent).
  static MouseCursor get grabbing => _grabbing(null);

  /// [grab] בגודל של התצוגה ש-[context] מוצג בה.
  static MouseCursor grabOf(BuildContext context) => _grab(_viewOf(context));

  /// [grabbing] בגודל של התצוגה ש-[context] מוצג בה.
  static MouseCursor grabbingOf(BuildContext context) =>
      _grabbing(_viewOf(context));

  static MouseCursor _grab(ui.FlutterView? view) =>
      Platform.isWindows ? _WindowsHandCursor(view) : SystemMouseCursors.grab;

  static MouseCursor _grabbing(ui.FlutterView? view) => Platform.isWindows
      ? _WindowsHandCursor(view)
      : SystemMouseCursors.grabbing;

  // בלי רישום תלות: נקרא גם מחוץ ל-build.
  static ui.FlutterView? _viewOf(BuildContext context) =>
      context.findAncestorWidgetOfExactType<View>()?.view;

  /// גודל הסמן בפיקסלים לוגיים.
  static const double _size = 18;

  static bool _initStarted = false;
  static final Map<double, Future<String?>> _cursorsByDpr = {};

  /// יוצר את הסמן ל-DPR הנוכחי ברקע (Windows בלבד); DPR אחר נוצר בשימוש
  /// הראשון בו. עד לסיום — ואם היצירה נכשלת — נשארת יד המערכת (IDC_HAND).
  static Future<void> ensureInitialized() async {
    if (_initStarted || !Platform.isWindows) return;
    _initStarted = true;
    await _cursorFor(_currentDpr());
  }

  static double _currentDpr() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 1.0 : views.first.devicePixelRatio;
  }

  /// שם הסמן הרשום במנוע עבור [dpr], או null אם היצירה נכשלה.
  static Future<String?> _cursorFor(double dpr) =>
      _cursorsByDpr.putIfAbsent(dpr, () async {
        try {
          final pixels = (_size * dpr).round();
          final image = await _paintHandImage(pixels.toDouble());
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          // המנוע מצפה ל-BGRA.
          final bgra = bytes!.buffer.asUint8List();
          for (var i = 0; i < bgra.length; i += 4) {
            final red = bgra[i];
            bgra[i] = bgra[i + 2];
            bgra[i + 2] = red;
          }
          final name = 'otzaria-hand@$dpr';
          await SystemChannels.mouseCursor.invokeMethod<String>(
            'createCustomCursor/windows',
            <String, Object>{
              'name': name,
              'buffer': bgra,
              'width': pixels,
              'height': pixels,
              'hotX': pixels / 2,
              'hotY': pixels / 2,
            },
          );
          return name;
        } catch (e) {
          debugPrint('AppCursors: falling back to system cursor: $e');
          return null;
        }
      });

  /// מצייר את היד כמו אייקון שורת הפקדים — קווי המתאר של הגליף הרגיל
  /// בשחור, וכף היד ממולאת לבן (הגליף הממולא מתחתיו כסילואטה).
  static Future<ui.Image> _paintHandImage(double pixelSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    void draw(IconData icon, Color color) {
      final painter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: pixelSize,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (pixelSize - painter.width) / 2,
          (pixelSize - painter.height) / 2,
        ),
      );
    }

    draw(FluentIcons.hand_left_24_filled, Colors.white);
    draw(FluentIcons.hand_left_24_regular, Colors.black);

    return recorder.endRecording().toImage(
      pixelSize.round(),
      pixelSize.round(),
    );
  }
}

class _WindowsHandCursor extends MouseCursor {
  const _WindowsHandCursor(this.view);

  /// התצוגה שה-DPR שלה נקרא בהפעלה; null — התצוגה הראשונה.
  final ui.FlutterView? view;

  @override
  MouseCursorSession createSession(int device) =>
      _WindowsHandCursorSession(this, device);

  @override
  String get debugDescription => 'AppCursors.hand';

  // MouseTracker מחליף סשן רק כשהסמן שונה; סמן לכל build לא יפעיל מחדש.
  @override
  bool operator ==(Object other) =>
      other is _WindowsHandCursor && other.view == view;

  @override
  int get hashCode => Object.hash(_WindowsHandCursor, view);
}

class _WindowsHandCursorSession extends MouseCursorSession {
  _WindowsHandCursorSession(_WindowsHandCursor super.cursor, super.device);

  bool _disposed = false;

  @override
  Future<void> activate() async {
    final name = AppCursors._initStarted
        ? await AppCursors._cursorFor(
            (cursor as _WindowsHandCursor).view?.devicePixelRatio ??
                AppCursors._currentDpr(),
          )
        : null;
    // סמן אחר הופעל בזמן שהסמן ל-DPR הזה נוצר.
    if (_disposed) return;
    if (name == null) {
      return SystemChannels.mouseCursor.invokeMethod<void>(
        'activateSystemCursor',
        <String, Object>{'device': device, 'kind': 'click'},
      );
    }
    return SystemChannels.mouseCursor.invokeMethod<void>(
      'setCustomCursor/windows',
      <String, Object>{'name': name},
    );
  }

  @override
  void dispose() => _disposed = true;
}
