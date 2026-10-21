import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/ref_key.dart';

void main() {
  test('הטוקנים של הכותרת מחושבים פעם אחת לכל שורות הספר', () {
    final first = titleTokens('משנה ברורה');

    expect(first, refKeyTokens('משנה ברורה'));
    expect(identical(titleTokens('משנה ברורה'), first), isTrue);
    expect(titleTokens('קיצור שולחן ערוך'), refKeyTokens('קיצור שולחן ערוך'));
    expect(identical(titleTokens('משנה ברורה'), first), isFalse);
  });

  test('מעבר בין כותרות אינו משאיר טוקנים של ספר קודם', () {
    // heRef שאינו מתחיל בכותרת כלשונה עובר בהשוואת הטוקנים.
    const cases = [
      ('משנה ברורה, סימן א, סעיף ב', 'משנה ברורה'),
      ('פרק א, סעיף ב', 'הערות שלי'),
      ('משנה  ברורה, סימן ג', 'משנה ברורה'),
      ('ספר המצות', 'ספר המצות'),
      ('קיצור שולחן ערוך, סימן ד', 'משנה ברורה'),
      ('פרק ה', ''),
    ];
    final expected = [
      'א ב',
      'א ב',
      'ג',
      null,
      'קיצור שולחן ערוך ד',
      'ה',
    ];

    for (var round = 0; round < 2; round++) {
      expect([
        for (final (heRef, title) in cases) buildLineRefKey(heRef, [title]),
      ], expected);
    }
  });
}
