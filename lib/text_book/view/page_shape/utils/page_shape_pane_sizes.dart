import 'dart:math' as math;

/// החלק המרבי שכל טור צד יכול לתפוס מרוחב הדף.
const double kPageShapeSideMaxFraction = 0.4;

/// החלק המזערי מרוחב הדף שנשאר תמיד לטקסט הראשי.
const double kPageShapeMainMinFraction = 0.3;

/// רוחב מזערי לטור צד, כדי שכפתורי טור ריק לא יגלשו בחלון צר.
const double kPageShapeSideMinWidth = 80.0;

/// גדלי הטורים נשמרים כחלק יחסי מהדף; ערך מעל 1 הוא פיקסלים מגרסה קודמת
/// ומומר ביחס ל-[legacyExtent]. מחזיר null כשאין גודל חלון להמרה.
double? pageShapeStoredFraction(double stored, double legacyExtent) {
  if (stored <= 1) return stored;
  if (legacyExtent <= 0) return null;
  return pageShapeFraction(stored, legacyExtent);
}

/// גודל בפיקסלים כחלק מ-[extent]; לא עולה על 1 כדי שלא ייקרא כפיקסלים.
double pageShapeFraction(double pixels, double extent) =>
    extent <= 0 ? 0 : math.min(1.0, pixels / extent);

/// רוחבי טורי הצד בפיקסלים לפי היחס השמור, כך שיחד לא ידחקו את הטקסט
/// הראשי מתחת ל-[kPageShapeMainMinFraction], וכל טור לפחות [kPageShapeSideMinWidth].
({double left, double right}) resolvePageShapeSideWidths({
  required double freeWidth,
  required double leftFraction,
  required double rightFraction,
  required bool hasLeft,
  required bool hasRight,
}) {
  final width = math.max(0.0, freeWidth);
  var left = math.min(leftFraction, kPageShapeSideMaxFraction) * width;
  var right = math.min(rightFraction, kPageShapeSideMaxFraction) * width;
  final used = (hasLeft ? left : 0.0) + (hasRight ? right : 0.0);
  final available = width * (1 - kPageShapeMainMinFraction);
  if (used > available && used > 0) {
    final scale = available / used;
    left *= scale;
    right *= scale;
  }
  return (
    left: math.max(left, kPageShapeSideMinWidth),
    right: math.max(right, kPageShapeSideMinWidth),
  );
}
