import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// המימוש הקודם של [quotedWordsOf], מועתק כלשונו — האורקל.
Set<String> _oldQuotedWordsOf(String raw, String Function(String) normalize) {
  final out = <String>{};
  for (final word in raw.split(RegExp(r'[\s,.:;()\[\]־-]+'))) {
    if (!_oldHasInnerQuote(word)) continue;
    final n = normalize(word);
    if (n.isNotEmpty && !n.contains(' ')) out.add(n);
  }
  return out;
}

bool _oldHasInnerQuote(String word) {
  for (var i = 1; i < word.length - 1; i++) {
    final c = word.codeUnitAt(i);
    if (c == 0x22 || c == 0x27 || c == 0x05F3 || c == 0x05F4) return true;
  }
  return false;
}

String _identity(String s) => s;

void _expectSame(String raw) {
  for (final normalize in [_identity, normalizeForFindRefMatch]) {
    expect(
      quotedWordsOf(raw, normalize),
      _oldQuotedWordsOf(raw, normalize),
      reason: raw.codeUnits.map((c) => c.toRadixString(16)).join(' '),
    );
  }
}

void main() {
  group('quotedWordsOf זהה למימוש הקודם (perf)', () {
    test('כל יחידת קוד כמפריד בין מילים, בתוך מילה ובקצותיה', () {
      for (var c = 0; c <= 0xFFFF; c++) {
        final ch = String.fromCharCode(c);
        _expectSame('א"ב$chג"ד');
        _expectSame('א$chב"ג');
        _expectSame('$ch"א$ch');
        _expectSame(ch);
      }
    });

    test('מחרוזות אקראיות מגרשיים, מפרידים, רווחים ואותיות', () {
      const alphabet = [
        'א',
        'ב',
        'ם',
        'a',
        '1',
        '"',
        "'",
        '׳',
        '״',
        ' ',
        '  ',
        '\t',
        '\n',
        ',',
        '.',
        ':',
        ';',
        '(',
        ')',
        '[',
        ']',
        '־',
        '-',
        '\u0085',
        '\u00A0',
        '\u2009',
        '\u3000',
        '\uFEFF',
        '\u200B',
        '\u180E',
        '\u{1F600}',
        '_',
      ];
      final random = Random(2375);
      for (var i = 0; i < 20000; i++) {
        final length = random.nextInt(14);
        _expectSame(
          [
            for (var j = 0; j < length; j++)
              alphabet[random.nextInt(alphabet.length)],
          ].join(),
        );
      }
    });

    test('כינויים ושאילתות אמיתיים', () {
      for (final raw in [
        'רמב"ם הלכות שבת',
        'שו"ע או"ח סי\' א',
        'הרמב"ם, (ראב"ד) [מ"ב]',
        'משנה ברורה',
        '"שבת"',
        'ע"א-ע"ב',
        '',
      ]) {
        _expectSame(raw);
      }
    });
  });
}
