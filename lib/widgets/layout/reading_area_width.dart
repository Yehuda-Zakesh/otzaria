import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// רוחב אזור הקריאה המלא, לפני שחלונית צד פתוחה דוחקת את התוכן. משמש בסיס
/// לחישוב רוחב עמודת הטקסט, כדי שפתיחת חלונית תזיז את הטקסט ולא תצר אותו.
class ReadingAreaWidth extends InheritedWidget {
  final double width;

  const ReadingAreaWidth({
    super.key,
    required this.width,
    required super.child,
  });

  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReadingAreaWidth>()?.width;

  @override
  bool updateShouldNotify(ReadingAreaWidth oldWidget) =>
      width != oldWidget.width;
}

/// רוחב מרבי לעמודת הטקסט לפי הגדרת "רוחב הטקסט".
///
/// [setting]: 0 = ללא הגבלה, ערך שלילי = רמה (-11 = 45%), ערך חיובי = פיקסלים
/// (פורמט ישן). האחוז מחושב מ-[baseWidth], והתוצאה מוגבלת ל-[availableWidth]
/// כך שהעמודה מצטמצמת רק כשאין מקום.
double resolveTextColumnMaxWidth({
  required double setting,
  required double availableWidth,
  required double baseWidth,
}) {
  if (setting == 0) return 0;
  final desired = setting > 0
      ? setting
      : baseWidth * (1.0 - (-setting).toInt() * 0.05);
  return math.min(desired, availableWidth);
}

/// [resolveTextColumnMaxWidth] כשהבסיס מגיע מ-[ReadingAreaWidth] העוטף.
double textColumnMaxWidthOf(
  BuildContext context, {
  required double setting,
  required double availableWidth,
}) {
  return resolveTextColumnMaxWidth(
    setting: setting,
    availableWidth: availableWidth,
    baseWidth: ReadingAreaWidth.maybeOf(context) ?? availableWidth,
  );
}
