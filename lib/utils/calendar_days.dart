/// מוסיף ימי לוח ולא 24 שעות: ביום מעבר שעון היום ארוך או קצר משעה.
DateTime addCalendarDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// מספר ימי הלוח מ-[from] עד [to], בלי תלות בשעה ביום ובמעברי שעון.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
