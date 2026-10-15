import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/calendar_days.dart';

import '../test_helpers/dst_days.dart';

void main() {
  test('calendarDaysBetween ignores the time of day', () {
    expect(
      calendarDaysBetween(DateTime(2026, 12, 31, 23, 59), DateTime(2027, 1, 1)),
      1,
    );
    expect(
      calendarDaysBetween(DateTime(2026, 3, 1), DateTime(2026, 2, 1)),
      -28,
    );
    expect(
      calendarDaysBetween(DateTime(2026, 5, 5, 8), DateTime(2026, 5, 5)),
      0,
    );
  });

  group('Across a DST change', skip: noDstSkipReason, () {
    for (final hours in [23, 25]) {
      test('$hours-hour day', () {
        final day = localDayLasting(hours)!;
        final next = plusDays(day, 1);
        expect(day.add(const Duration(days: 1)), isNot(next));
        expect(addCalendarDays(day, 1), next);
        expect(addCalendarDays(next, -1), day);
        expect(addCalendarDays(plusDays(day, -3), 7), plusDays(day, 4));
        expect(calendarDaysBetween(day, next), 1);
        expect(calendarDaysBetween(plusDays(day, -1), plusDays(day, 2)), 3);
        expect(
          calendarDaysBetween(atHour(day, 23, 30), atHour(next, 0, 10)),
          1,
        );
      });
    }
  });
}
