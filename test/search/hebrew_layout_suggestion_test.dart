import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/hebrew_layout_suggestion.dart';

/// issue #975 — הצעת תיקון להקלדה עברית שנעשתה במצב מקלדת אנגלי.
/// ההמרה לפי מיקום פיזי במקלדת (SI-1452 מול QWERTY), והיא הצעה בלבד.
void main() {
  group('suggestHebrewKeyboardFix — המרה לפי מיקום מקשים', () {
    test('הדוגמה מגוגל: ",heui veksv ctbdkh," → תיקון הקלדה באנגלית', () {
      expect(
        suggestHebrewKeyboardFix(',heui veksv ctbdkh,'),
        'תיקון הקלדה באנגלית',
      );
    });

    test('akuo → שלום (אותיות סופיות נופלות במקום הנכון מהמקש עצמו)', () {
      expect(suggestHebrewKeyboardFix('akuo'), 'שלום');
    });

    test('אותיות רישיות ממופות כמו קטנות', () {
      expect(suggestHebrewKeyboardFix('AKUO'), 'שלום');
    });

    test('רווחים, ספרות וגרשיים כפולים עוברים כמות שהם', () {
      expect(suggestHebrewKeyboardFix('akuo 123 "guko"'), 'שלום 123 "עולם"');
    });

    test('מקשי פיסוק שממופים לאותיות: נקודה-פסיק לףֳ, פסיק לת', () {
      // בדיקת ";" → ף וכן "," → ת בתוך מילה: ",uc" → תוב? נבדוק מילה אמיתית:
      // הקלדת "כסף" במצב אנגלי: כ=f ס=x ף=; → "fx;"
      expect(suggestHebrewKeyboardFix('fx;'), 'כסף');
    });
  });

  group('suggestHebrewKeyboardFix — מתי לא מציעים', () {
    test('שאילתה שכבר מכילה עברית — עירוב מכוון, אין הצעה', () {
      expect(suggestHebrewKeyboardFix('שלום akuo'), isNull);
    });

    test('אות לטינית בודדת — רעש, אין הצעה', () {
      expect(suggestHebrewKeyboardFix('a'), isNull);
      expect(suggestHebrewKeyboardFix('a 123'), isNull);
    });

    test('שאילתה ריקה או ללא אותיות בכלל', () {
      expect(suggestHebrewKeyboardFix(''), isNull);
      expect(suggestHebrewKeyboardFix('123 456'), isNull);
    });

    test('אותיות שממופות לפיסוק בלבד (q, w) — אין עברית בתוצאה, אין הצעה', () {
      expect(suggestHebrewKeyboardFix('qw'), isNull);
    });

    test('ההצעה לעולם אינה זהה למקור', () {
      // תווים לא-ממופים בלבד לא מגיעים לכאן (אין 2 אותיות לטיניות),
      // אבל ליתר ביטחון — התוצאה חייבת להיות שונה.
      final result = suggestHebrewKeyboardFix('akuo');
      expect(result, isNot('akuo'));
    });
  });
}
