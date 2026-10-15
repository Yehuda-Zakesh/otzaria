import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// המימוש הקודם לאירוע לא חוזר, להשוואה. [days] סופר ימים בין חצות לחצות.
bool _referenceOccursOn(
  CustomEvent e,
  DateTime date, [
  int Function(Duration) days = _inDays,
]) {
  final current = _dateOnly(date);
  final start = _dateOnly(e.baseGregorianDate);
  final durationDays = e.endGregorianDate == null
      ? 0
      : days(_dateOnly(e.endGregorianDate!).difference(start)).clamp(0, 366);
  return !current.isBefore(start) &&
      days(current.difference(start)) <= durationDays;
}

int _inDays(Duration d) => d.inDays;
int _calendarDays(Duration d) => (d.inHours / 24).round();

CustomEvent _event(int i, DateTime start, DateTime? end) => CustomEvent(
  id: '$i',
  title: 'e$i',
  description: '',
  createdAt: start,
  baseGregorianDate: start,
  baseJewishYear: 5786,
  baseJewishMonth: 1,
  baseJewishDay: 1,
  recurrenceType: RecurrenceType.none,
  endGregorianDate: end,
);

List<CustomEvent> _events() {
  final events = <CustomEvent>[];
  final base = DateTime(2025, 12, 1, 9, 30);
  const endOffsets = <int?>[null, 0, 1, 2, 6, -3, 400];
  for (var i = 0; i < 140; i++) {
    final hour = i.isEven ? 0 : base.hour;
    final start = DateTime(base.year, base.month, base.day + i, hour);
    for (final offset in endOffsets) {
      final end = offset == null
          ? null
          : DateTime(
              start.year,
              start.month,
              start.day + offset,
              i.isEven ? 18 : 0,
            );
      events.add(_event(events.length, start, end));
    }
  }
  return events;
}

List<DateTime> _dates() => [
  for (var i = 0; i < 400; i++) DateTime(2025, 11, 20 + i, i % 24),
];

void main() {
  test('אירוע לא חוזר: occursOn זהה למימוש הקודם בכל יום', () {
    final events = _events();
    for (final date in _dates()) {
      for (final e in events) {
        // ספירת שעות לעומת ימי לוח ביום מעבר שעון נבדקת ב-calendar_dst_test.
        if (_referenceOccursOn(e, date) !=
            _referenceOccursOn(e, date, _calendarDays)) {
          continue;
        }
        expect(
          e.occursOn(date),
          _referenceOccursOn(e, date),
          reason: 'event ${e.id} on $date',
        );
      }
    }
  });
}
