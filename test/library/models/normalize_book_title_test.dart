import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';

/// המימוש המקורי — מקור האמת להשוואה.
String _oracle(String title) => title
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll('"', '')
    .replaceAll("'", '')
    .replaceAll('״', '')
    .replaceAll('׳', '')
    .replaceAll('<', '')
    .replaceAll('>', '');

void main() {
  test('כותרת נקייה מוחזרת כמות שהיא, בלי בניית מחרוזות', () {
    final title = String.fromCharCodes('ספר אישי כלשהו'.codeUnits);
    expect(identical(normalizeBookTitle(title), title), isTrue);
  });

  test('זהה למימוש המקורי בכל צירוף של תווים מיוחדים', () {
    const fragments = [
      'א',
      'x',
      ' ',
      '  ',
      '"',
      "'",
      '״',
      '׳',
      '<',
      '>',
      '\t',
      '\n',
      ' ',
      '\u0085',
      ' ',
      ' ',
      ' ',
      '　',
      '﻿',
    ];
    final inputs = <String>[''];
    for (final a in fragments) {
      for (final b in fragments) {
        for (final c in fragments) {
          inputs.add('$a$b$c');
        }
      }
    }
    inputs.addAll(const [
      'שו"ע אורח חיים',
      'ר\' חיים',
      ' ברכות ',
      'בבא  קמא',
      '<ספר> "מיוחד"',
      'משנה תורה, הלכות ברכות',
    ]);
    for (final input in inputs) {
      expect(
        normalizeBookTitle(input),
        _oracle(input),
        reason: input.runes.toString(),
      );
    }
  });
}
