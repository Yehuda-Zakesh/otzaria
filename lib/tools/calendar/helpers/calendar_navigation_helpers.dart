// lib/tools/calendar/helpers/calendar_navigation_helpers.dart

import 'dart:math';

/// מזיזה תאריך לועזי לחודש הבא או הקודם תוך שמירה על אותו יום אם אפשר.
///
/// אם היום המבוקש לא קיים בחודש היעד, מחזיר את היום האחרון הזמין.
DateTime shiftGregorianMonthPreservingDay(
  DateTime current, {
  required bool forward,
}) {
  final targetYear = forward
      ? (current.month == 12 ? current.year + 1 : current.year)
      : (current.month == 1 ? current.year - 1 : current.year);
  final targetMonth = forward
      ? (current.month == 12 ? 1 : current.month + 1)
      : (current.month == 1 ? 12 : current.month - 1);
  final targetDaysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;
  final targetDay = min(current.day, targetDaysInMonth);
  return DateTime(targetYear, targetMonth, targetDay);
}
