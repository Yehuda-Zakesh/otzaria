import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/ref_key.dart';

void main() {
  test('תו של טוקן הוא בדיוק מה שהנרמול הקודם לא החליף ברווח', () {
    final keyChar = RegExp(r'[a-zA-Z0-9֐-׿]');
    for (var c = 0; c <= 0xFFFF; c++) {
      expect(
        isRefKeyChar(c),
        keyChar.hasMatch(String.fromCharCode(c)),
        reason: 'U+${c.toRadixString(16)}',
      );
    }
  });

  test('כל תו אחר מפריד בין טוקנים, ורק אותיות לטיניות מוקטנות', () {
    const cases = {
      'Gen\t1 ב　ג': ['gen', '1', 'ב', 'ג'],
      'a.b/c—d,,  e': ['a', 'b', 'c', 'd', 'e'],
      'XKY': ['x', 'y'],
      'İstanbul 😀 סימן ב': ['stanbul', 'ב'],
      'ABC־דף\nפרק ג': ['abc', 'ג'],
      ' ,; ': <String>[],
    };
    cases.forEach((ref, tokens) {
      expect(refKeyTokens(ref), tokens, reason: ref);
    });
  });
}
