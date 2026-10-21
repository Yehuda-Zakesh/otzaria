import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

import '../../test_helpers/reading_toc.dart';

void main() {
  group('isReadingHeaderLine', () {
    test('מזהה תגי כותרת h1–h6', () {
      for (final tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']) {
        expect(
          isReadingHeaderLine('<$tag>title</$tag>'),
          isTrue,
          reason: 'תג $tag צריך להיחשב ככותרת',
        );
      }
    });

    test('סובלני לרווחים מובילים ול-case-insensitive', () {
      expect(isReadingHeaderLine('  <H2 class="x">פרק</H2>'), isTrue);
    });

    test('שורה רגילה אינה כותרת', () {
      expect(isReadingHeaderLine('בראשית ברא אלהים'), isFalse);
      expect(isReadingHeaderLine('<p>פסקה</p>'), isFalse);
      expect(isReadingHeaderLine('<h7>not a header</h7>'), isFalse);
    });
  });

  group('isAlignedBlockLine', () {
    test('מזהה div עם text-align ו-center, גם אחרי עוגנים ו-br', () {
      expect(
        isAlignedBlockLine('<div style="text-align: center;">טקסט</div>'),
        isTrue,
      );
      expect(
        isAlignedBlockLine('<DIV STYLE="TEXT-ALIGN:left">x</DIV>'),
        isTrue,
      );
      expect(isAlignedBlockLine('<br><center><b>הדרן</b></center>'), isTrue);
      expect(
        isAlignedBlockLine(
          '<a id="b1"></a><a id="b2"></a><div style="text-align: right;">x</div>',
        ),
        isTrue,
      );
    });

    test('שורה רגילה או יישור באמצע השורה אינם בלוק מיושר', () {
      expect(isAlignedBlockLine('בראשית ברא אלהים'), isFalse);
      expect(isAlignedBlockLine('<div class="x">טקסט</div>'), isFalse);
      expect(isAlignedBlockLine('<centered>x</centered>'), isFalse);
      expect(
        isAlignedBlockLine('<a href="x">קישור</a><center>x</center>'),
        isFalse,
      );
      expect(
        isAlignedBlockLine('טקסט <div style="text-align: center;">x</div>'),
        isFalse,
      );
    });
  });

  group('דילוג על RegExp לשורת טקסט', () {
    test('שורות שמתחילות באות אינן מריצות את תבניות הכותרת והיישור', () {
      final lines = [
        '<h2>פרק א</h2>',
        for (var i = 0; i < 500; i++) 'בראשית ברא אלהים $i',
        '<center>הדרן</center>',
      ];
      for (final continuous in [false, true]) {
        debugReadingTagPatternChecks = 0;
        final segments = buildReadingSegments(
          lines,
          continuous: continuous,
          loadedLineFlags: List<bool>.filled(lines.length, true),
        );
        for (var i = 0; i < segments.length; i++) {
          segments[i];
        }
        expect(debugReadingTagPatternChecks, inInclusiveRange(2, 6));
      }
    });

    test('התוצאה זהה ל-RegExp המלא לכל תו ראשון אפשרי', () {
      final header = RegExp(r'^\s*<h[1-6]', caseSensitive: false);
      final aligned = RegExp(
        r'^\s*(?:(?:<a\b[^>]*>\s*</a>|<br\s*/?>)\s*)*'
        r'<(?:center\b|div\b[^>]*\btext-align\s*:)',
        caseSensitive: false,
      );
      final prefixes = [
        '',
        for (var c = 0; c <= 0xFFFF; c++) String.fromCharCode(c),
      ];
      const bodies = [
        '<h3>כותרת</h3>',
        '<center>x</center>',
        '<br><div style="text-align:center">x</div>',
        'טקסט',
      ];
      for (final prefix in prefixes) {
        for (final body in bodies) {
          final line = '$prefix$body';
          expect(
            isReadingHeaderLine(line),
            header.hasMatch(line),
            reason: line,
          );
          expect(
            isAlignedBlockLine(line),
            aligned.hasMatch(line),
            reason: line,
          );
        }
      }
    });
  });

  group('buildReadingSegments — non-continuous', () {
    test('שורה אחת לכל סגמנט במצב הרגיל', () {
      final lines = ['<h1>פתיחה</h1>', 'שורה א', 'שורה ב', 'שורה ג'];
      final segments = buildReadingSegments(lines, continuous: false);

      expect(segments, hasLength(4));
      for (var i = 0; i < segments.length; i++) {
        expect(segments[i].sourceLineIndices, [i]);
        expect(segments[i].text, lines[i]);
      }
      expect(segments[0].isHeader, isTrue);
      expect(segments[1].isHeader, isFalse);
    });

    test('lineRanges במצב רגיל מכסים את כל השורה', () {
      final lines = ['שורה ראשונה', 'שניה'];
      final segments = buildReadingSegments(lines, continuous: false);

      expect(segments[0].lineRanges, hasLength(1));
      expect(segments[0].lineRanges.first.start, 0);
      expect(segments[0].lineRanges.first.end, lines[0].length);
    });
  });

  group('buildReadingSegments — continuous', () {
    test('שורות לא־כותרת עוקבות מתמזגות לפסקה אחת', () {
      final lines = ['<h1>פרק א</h1>', 'אחת', 'שתיים', 'שלוש'];
      final segments = buildReadingSegments(lines, continuous: true);

      // כותרת בנפרד + פסקה אחת מאוחדת
      expect(segments, hasLength(2));
      expect(segments[0].isHeader, isTrue);
      expect(segments[0].sourceLineIndices, [0]);

      expect(segments[1].isHeader, isFalse);
      expect(segments[1].sourceLineIndices, [1, 2, 3]);
      expect(segments[1].text, 'אחת שתיים שלוש');
    });

    test('כותרת שוברת פסקה רציפה', () {
      final lines = [
        'שורה לפני',
        '<h2>כותרת</h2>',
        'שורה אחרי',
      ];
      final segments = buildReadingSegments(lines, continuous: true);

      expect(segments, hasLength(3));
      expect(segments[0].sourceLineIndices, [0]);
      expect(segments[1].isHeader, isTrue);
      expect(segments[1].sourceLineIndices, [1]);
      expect(segments[2].sourceLineIndices, [2]);
    });

    test('lineRanges פסקאיים מצביעים על מיקום מדויק בטקסט המאוחד', () {
      final lines = ['אאא', 'בבב'];
      final segments = buildReadingSegments(lines, continuous: true);

      expect(segments, hasLength(1));
      final segment = segments.first;
      expect(segment.text, 'אאא בבב');
      // השורה הראשונה היא 0..3, ואז רווח, ואז השורה השניה ב-4..7
      expect(segment.lineRanges[0].start, 0);
      expect(segment.lineRanges[0].end, 3);
      expect(segment.lineRanges[1].start, 4);
      expect(segment.lineRanges[1].end, 7);
    });

    test('שורות ריקות נשמרות כאינדקסים אך מתמזגות', () {
      final lines = ['א', '', 'ג'];
      final segments = buildReadingSegments(lines, continuous: true);

      expect(segments, hasLength(1));
      expect(segments.first.sourceLineIndices, [0, 1, 2]);
    });

    test('פסקה שחלק משורותיה לא נטען נשארת פריט אחד שאינו טעון', () {
      final lines = ['', '', 'א', 'ב'];
      final segments = buildReadingSegments(
        lines,
        continuous: true,
        loadedLineFlags: const [false, false, true, true],
      );

      expect(segments, hasLength(1));
      expect(segments[0].isLoaded, isFalse);
      expect(segments[0].sourceLineIndices, [0, 1, 2, 3]);
      expect(segments[0].text, isEmpty);
    });

    test('רשימה ריקה לא נופלת', () {
      expect(buildReadingSegments(const [], continuous: true), isEmpty);
      expect(buildReadingSegments(const [], continuous: false), isEmpty);
    });
  });

  group('segmentIndexForLine', () {
    test('שורה שנמצאת בסגמנט מחזירה את האינדקס שלו', () {
      // continuous: כל שורה לא-כותרת באותה פסקה
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: true);
      // פסקה אחת לכל השורות
      expect(segmentIndexForLine(segments, 0), 0);
      expect(segmentIndexForLine(segments, 1), 0);
      expect(segmentIndexForLine(segments, 2), 0);
    });

    test('עם כותרת — מחזירה סגמנטים שונים', () {
      final segments = buildReadingSegments(
        ['<h1>כותרת</h1>', 'א', 'ב'],
        continuous: true,
      );
      // [header(0), paragraph(1,2)]
      expect(segmentIndexForLine(segments, 0), 0);
      expect(segmentIndexForLine(segments, 1), 1);
      expect(segmentIndexForLine(segments, 2), 1);
    });

    test('שורה לפני הסגמנט הראשון מחזירה 0', () {
      final segments = buildReadingSegments(['א', 'ב'], continuous: false);
      expect(segmentIndexForLine(segments, -5), 0);
    });

    test('שורה מעבר לסוף מחזירה את האחרון', () {
      final segments = buildReadingSegments(['א', 'ב'], continuous: false);
      expect(segmentIndexForLine(segments, 100), 1);
    });

    test('רשימה ריקה — מחזיר 0', () {
      expect(
        segmentIndexForLine(
          buildReadingSegments(const [], continuous: true),
          5,
        ),
        0,
      );
    });
  });

  group('lineFractionWithinSegment', () {
    test('שורה ראשונה בפסקה — fraction = 0', () {
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: true);
      expect(lineFractionWithinSegment(segments.first, 0), 0);
    });

    test('שורה אמצעית בפסקה — fraction באמצע', () {
      final segments = buildReadingSegments([
        'א',
        'ב',
        'ג',
        'ד',
      ], continuous: true);
      // הטקסט הממוזג 'א ב ג ד' (7 תווים), שורה 2 מתחילה בתו 4 → 4/7.
      expect(
        lineFractionWithinSegment(segments.first, 2),
        closeTo(4 / 7, 1e-9),
      );
    });

    test('משקל שורה מתעלם מגוף הערת inline ומניקוד', () {
      const noteLine =
          'קצר<sup class="footnote-marker">א</sup>'
          '<i class="footnote">גוף הערה ארוך מאוד שמוסר לחלוטין ברינדור</i>';
      final segments = buildReadingSegments(
        ['אָאָאָאָ', noteLine, 'סוף'],
        continuous: true,
      );
      // תצוגה: 'אָאָאָאָ'=4 graphemes, noteLine='קצרא'=4, ורווח אחרי כל שורה
      // → שורה 2 מתחילה ב-10 מתוך 13.
      expect(
        lineFractionWithinSegment(segments.first, 2),
        closeTo(10 / 13, 1e-9),
      );
    });

    test('שקלול לפי אורך טקסט — שורה ארוכה מזיזה את השורות שאחריה', () {
      final segments = buildReadingSegments(
        ['אאאאאאאאאא', 'ב', 'ג'],
        continuous: true,
      );
      // 'אאאאאאאאאא ב ג' (14 תווים): שורה 1 מתחילה בתו 11 → 11/14,
      // הרבה אחרי 1/3 של חלוקה שווה.
      expect(
        lineFractionWithinSegment(segments.first, 1),
        closeTo(11 / 14, 1e-9),
      );
    });

    test('סגמנט שורה אחת מחזיר 0', () {
      final segments = buildReadingSegments(['א'], continuous: false);
      expect(lineFractionWithinSegment(segments.first, 0), 0);
    });

    test('intraLineFraction בסגמנט שורה אחת — מיקום ההתאמה בפסקה', () {
      final segments = buildReadingSegments(['א'], continuous: false);
      expect(
        lineFractionWithinSegment(segments.first, 0, intraLineFraction: 0.5),
        0.5,
      );
    });

    test('intraLineFraction בפסקה רב-שורתית משוקלל לפי אורך הטקסט', () {
      final segments = buildReadingSegments([
        'א',
        'ב',
        'ג',
        'ד',
      ], continuous: true);
      // 'א ב ג ד' (7 תווים): שורה 2 מתחילה בתו 4, רוחבה (כולל רווח מפריד)
      // 2 תווים, + חצי פנימה → (4 + 1)/7.
      expect(
        lineFractionWithinSegment(segments.first, 2, intraLineFraction: 0.5),
        closeTo(5 / 7, 1e-9),
      );
    });
  });

  group('sourceLineIndicesForSegmentViewports', () {
    test('סגמנט שורה אחת מחזיר את שורת המקור שלו', () {
      final segments = buildReadingSegments(['א', 'ב', 'ג'], continuous: false);
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 1,
            leadingEdge: 0,
            trailingEdge: 0.5,
          ),
        ],
      );
      expect(result, [1]);
    });

    test('סגמנט כותרת — תמיד מחזיר את שורת הכותרת בלי חישוב fraction', () {
      final segments = buildReadingSegments(
        ['<h1>title</h1>', 'a', 'b'],
        continuous: true,
      );
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: -100, // ערכים לא הגיוניים, צריך להתעלם
            trailingEdge: 100,
          ),
        ],
      );
      expect(result, [0]);
    });

    test('סגמנט unloaded גדול מחזיר רק פרוסה מייצגת קטנה', () {
      final segments = buildReadingSegments(
        List<String>.filled(1000, ''),
        continuous: true,
        loadedLineFlags: List<bool>.filled(1000, false),
      );

      final result = sourceLineIndicesForSegmentViewports(
        segments,
        const [
          ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: -10,
            trailingEdge: 10,
          ),
        ],
      );

      expect(result.length, lessThanOrEqualTo(3));
      expect(result.first, greaterThan(0));
      expect(result.last, lessThan(999));
    });

    test('סגמנט רב-שורתי — חישוב fraction מחזיר תת-קבוצה של שורות', () {
      // 4 שורות בפסקה אחת.
      final segments = buildReadingSegments([
        'a',
        'b',
        'c',
        'd',
      ], continuous: true);

      // viewport שמתחיל מעט לפני הסגמנט, מסתיים באמצעו:
      // leadingEdge=0, trailingEdge=1 → extent=1, startFraction=0, endFraction=1
      // → כל השורות צריכות להופיע.
      final all = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
        ],
      );
      expect(all, [0, 1, 2, 3]);
    });

    test('extent לא תקין — נופל ל-startLineIndex', () {
      final segments = buildReadingSegments(['a', 'b', 'c'], continuous: true);
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 0,
            leadingEdge: 0.5,
            trailingEdge: 0.5, // extent = 0
          ),
        ],
      );
      expect(result, [0]);
    });

    test('אינדקסים מחוץ לטווח מתעלמים בשקט', () {
      final segments = buildReadingSegments(['a'], continuous: false);
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: -1,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
          const ReadingSegmentViewport(
            segmentIndex: 99,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test('isLineRemnant מסנן שורות שנגמרות בקו העוגן בתוך סגמנט ממוזג', () {
      // 10 שורות בפסקה ממוזגת אחת. ניווט לשורה 5 מיישר אותה לקו העוגן
      // (0.05) לפי אותו שקלול שהניווט משתמש בו: הסגמנט תופס extent=1.0.
      final segments = buildReadingSegments(
        List<String>.generate(10, (i) => 'line$i'),
        continuous: true,
      );

      final targetFraction = lineFractionWithinSegment(segments.first, 5);
      final viewport = ReadingSegmentViewport(
        segmentIndex: 0,
        leadingEdge: 0.05 - targetFraction,
        trailingEdge: 0.05 - targetFraction + 1.0,
      );

      // בלי הסינון - שורות שמעל קו העוגן (כולל ריפוד) נכללות ראשונות.
      final unfiltered = sourceLineIndicesForSegmentViewports(segments, [
        viewport,
      ]);
      expect(unfiltered.first, lessThan(5));

      // עם הסינון - השורה שאליה ניווטו היא הראשונה.
      final filtered = sourceLineIndicesForSegmentViewports(
        segments,
        [viewport],
        isLineRemnant: isRemnantAbovePositionAnchor,
      );
      expect(filtered.first, 5);
      expect(filtered, contains(6));
    });

    test('viewports ממספר סגמנטים מחוברים יחד וממוינים', () {
      // 5 שורות: 0=header, 1-2 פסקה ראשונה, 3=header, 4 פסקה שניה
      final segments = buildReadingSegments(
        ['<h1>a</h1>', 'b', 'c', '<h1>d</h1>', 'e'],
        continuous: true,
      );
      // segments: [h(0), p(1,2), h(3), p(4)]
      final result = sourceLineIndicesForSegmentViewports(
        segments,
        [
          const ReadingSegmentViewport(
            segmentIndex: 1,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
          const ReadingSegmentViewport(
            segmentIndex: 3,
            leadingEdge: 0,
            trailingEdge: 1,
          ),
        ],
      );
      expect(result, [1, 2, 4]);
    });
  });
  group('פריטים בנויים בגלילה ארוכה', () {
    // ספר בלי TOC: כל פסקה ממוזגת מחזיקה עותק של טקסט שורותיה.
    final lines = [for (var i = 0; i < 2000; i++) 'שורה $i של הספר'];
    List<int> breaks() => [for (var i = 0; i < lines.length; i += 3) i];

    test('מעבר על כל הפריטים אינו שומר את כולם', () {
      final segments = buildReadingSegments(
        lines,
        continuous: true,
        breakLines: breaks(),
      );
      for (var i = 0; i < segments.length; i++) {
        segments[i];
      }
      expect(segments.length, greaterThan(kMaxBuiltReadingSegments));
      expect(segments.debugBuiltCount, kMaxBuiltReadingSegments);
    });

    test('פריט שנבנה מחדש זהה לבנייה הראשונה, ופריט שבשימוש נשמר', () {
      final segments = buildReadingSegments(
        lines,
        continuous: true,
        breakLines: breaks(),
      );
      final first = segments[1];
      final kept = segments[2];
      for (var i = 3; i < segments.length; i++) {
        segments[i];
        expect(identical(segments[2], kept), isTrue);
      }
      final rebuilt = segments[1];
      expect(identical(rebuilt, first), isFalse);
      expect(rebuilt.text, first.text);
      expect(rebuilt.sourceLineIndices, first.sourceLineIndices);
      expect(
        [for (final r in rebuilt.lineRanges) (r.lineIndex, r.start, r.end)],
        [for (final r in first.lineRanges) (r.lineIndex, r.start, r.end)],
      );
      expect(rebuilt.isHeader, first.isHeader);
      expect(rebuilt.isLoaded, first.isLoaded);
    });
  });
}
