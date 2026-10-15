/// היום הראשון ב-2026–2027 שאורכו המקומי [hours] שעות (23 או 25),
/// או null כשבאזור הזמן של המחשב אין שעון קיץ.
DateTime? localDayLasting(int hours) {
  for (var d = DateTime(2026); d.year < 2028; d = plusDays(d, 1)) {
    if (plusDays(d, 1).difference(d).inHours == hours) return d;
  }
  return null;
}

DateTime plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

DateTime shabbatOnOrAfter(DateTime day) {
  while (day.weekday != DateTime.saturday) {
    day = plusDays(day, 1);
  }
  return day;
}

DateTime atHour(DateTime d, int hour, [int minute = 0]) =>
    DateTime(d.year, d.month, d.day, hour, minute);

/// סיבת דילוג לבדיקות מעבר שעון; ב-UTC אין ימי מעבר.
String? get noDstSkipReason =>
    localDayLasting(23) == null || localDayLasting(25) == null
    ? 'local time zone has no DST (run with e.g. TZ=Asia/Jerusalem)'
    : null;
