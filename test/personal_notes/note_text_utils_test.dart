import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

void main() {
  group('splitBookContentIntoLines', () {
    test('מפצל לפי שורות ומנרמל \\r\\n', () {
      expect(
        splitBookContentIntoLines('שורה א\r\nשורה ב\nשורה ג'),
        ['שורה א', 'שורה ב', 'שורה ג'],
      );
    });

    test('מסיר שורה ריקה בסוף התוכן', () {
      expect(splitBookContentIntoLines('שורה א\nשורה ב\n'), [
        'שורה א',
        'שורה ב',
      ]);
    });

    test('שורות ריקות באמצע נשמרות', () {
      expect(splitBookContentIntoLines('א\n\nב'), ['א', '', 'ב']);
    });

    test('זהה למימוש הייחוס בקצוות: \\r בודד, ריקות וסיום', () {
      for (final input in [
        '',
        '\n',
        '\r\n',
        '\n\n',
        'א\r',
        'א\rב\nג',
        'א\r\r\nב',
        '\r\n\r\nא\r\n',
        'א\n\r\nב\n\n',
      ]) {
        expect(
          splitBookContentIntoLines(input),
          _oracleSplit(input),
          reason: 'קלט: ${input.codeUnits}',
        );
      }
    });

    test('זהה למימוש הייחוס על קלט אקראי עם \\r ו-\\n', () {
      const alphabet = ['א', 'ב', ' ', '\r', '\n', '\r\n'];
      for (var seed = 0; seed < 500; seed++) {
        final random = Random(seed);
        final input = [
          for (var i = random.nextInt(30); i > 0; i--)
            alphabet[random.nextInt(alphabet.length)],
        ].join();
        expect(
          splitBookContentIntoLines(input),
          _oracleSplit(input),
          reason: 'קלט: ${input.codeUnits}',
        );
      }
    });

    test('מהיר לפחות פי 1.5 מהמימוש הקודם על ספר גדול', () {
      final line = 'וְזֶה לְשׁוֹן הַשּׁוּלְחָן עָרוּךְ ' * 6;
      final content = List.filled(30000, line).join('\n');
      int timeMicros(List<String> Function(String) split) {
        final stopwatch = Stopwatch()..start();
        expect(split(content), hasLength(30000));
        return stopwatch.elapsedMicroseconds;
      }

      // מינימום של מדידות לסירוגין: מסנן הפרעות GC ו-JIT בסביבת CI עמוסה.
      var oracle = 1 << 62;
      var current = 1 << 62;
      for (var round = 0; round < 5; round++) {
        oracle = min(oracle, timeMicros(_oracleSplit));
        current = min(current, timeMicros(splitBookContentIntoLines));
      }
      expect(
        current * 3,
        lessThan(oracle * 2),
        reason: 'oracle ${oracle}us, current ${current}us',
      );
    });
  });

  group('extractReferenceWordsFromLine', () {
    test('מחלץ מילים עד למגבלה', () {
      final words = extractReferenceWordsFromLine(
        'אחת שתיים שלוש ארבע חמש',
        limit: 3,
      );
      expect(words, ['אחת', 'שתיים', 'שלוש']);
    });

    test('מסיר תגי HTML לפני חילוץ', () {
      final words = extractReferenceWordsFromLine(
        '<b>מילה</b> <span>נוספת</span>',
      );
      expect(words, ['מילה', 'נוספת']);
    });

    test('מדלג על מילים מכותרת הספר', () {
      final words = extractReferenceWordsFromLine(
        'בראשית ברא אלהים',
        excludeBookTitle: 'בראשית',
      );
      expect(words, ['ברא', 'אלהים']);
    });

    test('שורה ריקה מחזירה רשימה ריקה', () {
      expect(extractReferenceWordsFromLine(''), isEmpty);
    });
  });

  group('extractDisplayTextFromLine', () {
    test('מסיר ניקוד ותגי HTML', () {
      final text = extractDisplayTextFromLine('<b>בְּרֵאשִׁית בָּרָא</b>');
      expect(text, 'בראשית ברא');
    });

    test('מגביל את מספר המילים', () {
      final text = extractDisplayTextFromLine(
        'אחת שתיים שלוש ארבע חמש שש',
        maxWords: 2,
      );
      expect(text, 'אחת שתיים');
    });

    test('מדלג על מילות כותרת הספר', () {
      final text = extractDisplayTextFromLine(
        'בראשית ברא אלהים',
        excludeBookTitle: 'בראשית',
      );
      expect(text, 'ברא אלהים');
    });

    test('קוצץ תוצאה ארוכה מ-100 תווים', () {
      final longLine = List.filled(5, 'א' * 30).join(' ');
      final text = extractDisplayTextFromLine(longLine, maxWords: 5);
      expect(text.length, lessThanOrEqualTo(100));
    });

    test('שורה ריקה מחזירה מחרוזת ריקה', () {
      expect(extractDisplayTextFromLine(''), '');
      expect(extractDisplayTextFromLine('<br/>'), '');
    });
  });

  group('removeHebrewDiacritics', () {
    test('מסיר ניקוד וטעמים', () {
      expect(removeHebrewDiacritics('בְּרֵאשִׁ֖ית'), 'בראשית');
    });

    test('מחליף מקף עברי ברווח', () {
      expect(removeHebrewDiacritics('על־כן'), 'על כן');
    });
  });

  group('normalizeWord', () {
    test('מסיר סימני פיסוק ומשאיר אותיות וספרות', () {
      expect(normalizeWord('"שלום,'), 'שלום');
      expect(normalizeWord('123!'), '123');
    });

    test('מילה שכולה פיסוק מוחזרת לאחר trim', () {
      expect(normalizeWord(' ?! '), '?!');
    });
  });

  group('computeWordOverlapRatio', () {
    test('רשימה שמורה ריקה מחזירה 1.0', () {
      expect(computeWordOverlapRatio([], ['א']), 1.0);
    });

    test('רשימה בפועל ריקה מחזירה 0.0', () {
      expect(computeWordOverlapRatio(['א'], []), 0.0);
    });

    test('חפיפה מלאה מחזירה 1.0', () {
      expect(computeWordOverlapRatio(['א', 'ב'], ['ב', 'א']), 1.0);
    });

    test('חפיפה חלקית מחזירה את היחס הנכון', () {
      expect(computeWordOverlapRatio(['א', 'ב', 'ג', 'ד'], ['א', 'ב']), 0.5);
    });

    test('הנרמול מתעלם מסימני פיסוק בהשוואה', () {
      expect(computeWordOverlapRatio(['שלום,'], ['"שלום']), 1.0);
    });
  });
}

List<String> _oracleSplit(String content) {
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}
