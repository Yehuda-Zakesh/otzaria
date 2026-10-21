import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  // הכרעת הגרשיים בודקת כל תו סמוך בפרדיקט על יחידת הקוד, בלי מחרוזת ו-RegExp לתו.
  test('פרדיקטי התווים סביב גרשיים זהים לתבניות שהחליפו', () {
    final punctuation = RegExp(r'[!:;.,?\-—–\x00]');
    final letter = RegExp(r'[א-תa-zA-Z]');
    for (var unit = 0; unit <= 0xFFFF; unit++) {
      final char = String.fromCharCode(unit);
      expect(
        isQuoteAdjacentPunctuationUnit(unit),
        punctuation.hasMatch(char),
        reason: 'U+${unit.toRadixString(16)}',
      );
      expect(
        isAcronymLetterUnit(unit),
        letter.hasMatch(char),
        reason: 'U+${unit.toRadixString(16)}',
      );
    }
  });
}
