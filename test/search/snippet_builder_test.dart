import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/search/utils/snippet_builder.dart';

import '../support/search_engine_test_init.dart';

String _highlighted(List<InlineSpan> spans) => spans
    .whereType<TextSpan>()
    .where((span) => span.style?.fontWeight == FontWeight.bold)
    .map((span) => span.text ?? '')
    .join();

String _allText(List<InlineSpan> spans) =>
    spans.whereType<TextSpan>().map((span) => span.text ?? '').join();

const _defaultStyle = TextStyle();
const _highlightStyle = TextStyle(fontWeight: FontWeight.bold);

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  group('fromHighlightedHtml - הדגשות מהמנוע', () {
    test('מדגיש טקסט שעטוף בתג font ומשאיר את השאר רגיל', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: 'בראשית <font color="red">ברא</font> אלהים',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), 'ברא');
      expect(_allText(spans), contains('בראשית'));
      expect(_allText(spans), contains('אלהים'));
      // תגי ה-HTML עצמם אינם מוצגים.
      expect(_allText(spans), isNot(contains('font')));
    });

    test('מדגיש גם תג mark', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: 'שלום <mark>עולם</mark>',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), 'עולם');
    });

    test('markStyle חל על mark בלבד; font נשאר בהדגשה הרגילה', () {
      const markStyle = TextStyle(backgroundColor: Color(0x1F000000));
      final spans = SnippetBuilder.fromHighlightedHtml(
        html:
            'א <font color=red>ב</font> <mark>ג <b>ד</b></mark> '
            '<font color=red><mark>ה</mark></font>',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
        markStyle: markStyle,
      );
      String styled(TextStyle style) => spans
          .whereType<TextSpan>()
          .where((span) => identical(span.style, style))
          .map((span) => span.text)
          .join();

      expect(styled(markStyle), 'ג ד');
      // הדגשה חיצונית קובעת גם לתג שבתוכה.
      expect(styled(_highlightStyle), 'בה');
      expect(_allText(spans), 'א ב ג ד ה');
    });

    test('קינון font ו-mark: התג החיצוני קובע בשני הכיוונים', () {
      const markStyle = TextStyle(backgroundColor: Color(0x1F000000));
      final spans = SnippetBuilder.fromHighlightedHtml(
        html:
            '<mark>א <font color=red>ב</font></mark> '
            '<font color=red>ג <mark>ד</mark></font>',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
        markStyle: markStyle,
      );
      List<String?> textsWith(TextStyle style) => [
        for (final span in spans.whereType<TextSpan>())
          if (identical(span.style, style)) span.text,
      ];

      expect(textsWith(markStyle), ['א ', 'ב']);
      expect(textsWith(_highlightStyle), ['ג ', 'ד']);
      expect(textsWith(_defaultStyle), [' ']);

      // בלי markStyle שני התגים מקבלים את ההדגשה הרגילה, כמו קודם.
      final plain = SnippetBuilder.fromHighlightedHtml(
        html: '<mark>א <font color=red>ב</font></mark>',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );
      expect(_highlighted(plain), 'א ב');
    });

    test('תגי עיצוב של תוכן הספר (b) אינם נחשבים הדגשת חיפוש', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: '<b>כותרת</b> טקסט רגיל',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), isEmpty);
      expect(_allText(spans), contains('כותרת'));
      expect(_allText(spans), contains('טקסט רגיל'));
    });

    test('<br> של ביטוי שנמשך לשורה הבאה הופך למעבר שורה אמיתי', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html:
            'ובין <font color=red>המים</font><br><font color=red>ויאמר</font> אלהים',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_allText(spans), 'ובין המים\nויאמר אלהים');
      expect(_highlighted(spans), 'המיםויאמר');
    });

    test('מעבר שורה בתוך הטקסט עצמו עדיין מתכווץ לרווח', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: 'שורה\nאחת',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_allText(spans), 'שורה אחת');
    });
  });

  group('extractHighlightedTerms - חילוץ מונחי התאמה להדגשת PDF', () {
    test('מחלץ את תוכן תגי font ו-mark בלבד, ללא כפילויות', () {
      final terms = SnippetBuilder.extractHighlightedTerms(
        'בראשית <font color="red">ברא</font> אלהים '
        '<mark>שבתות</mark> וגם <font color="red">ברא</font>',
      );
      expect(terms, {'ברא', 'שבתות'});
    });

    test('תגי עיצוב של תוכן הספר (b) אינם נחשבים התאמה', () {
      final terms = SnippetBuilder.extractHighlightedTerms(
        '<b>כותרת</b> טקסט <font>מצא</font>',
      );
      expect(terms, {'מצא'});
    });

    test('HTML ללא תגי הדגשה מחזיר קבוצה ריקה', () {
      expect(
        SnippetBuilder.extractHighlightedTerms('טקסט רגיל בלי הדגשות'),
        isEmpty,
      );
    });

    test('מנרמל רווחים בתוך מונח מודגש', () {
      final terms = SnippetBuilder.extractHighlightedTerms(
        '<font>אבג   דהו</font>',
      );
      expect(terms, {'אבג דהו'});
    });
  });

  group(
    'highlightLiteral - חיפוש מקומי',
    () {
      test('מדגיש את השאילתה הליטרלית', () {
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'אמר שלום לכל אדם',
          query: 'שלום',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), 'שלום');
      });

      test('סובלני לניקוד בטקסט המוצג', () {
        // "פַרעה" — פ עם פתח ואחריה רעה.
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'פַרעה אמר',
          query: 'פרעה',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        final stripped = _highlighted(spans).replaceAll(RegExp(r'[֑-ׇ]'), '');
        expect(stripped, 'פרעה');
      });

      test('מכבד גבולות מילה ולא מדגיש חלק ממילה', () {
        // "אמר" מופיע בתוך "נאמרו" ולכן אסור להדגיש.
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'נאמרו דברים',
          query: 'אמר',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), isEmpty);
      });

      test('מתאים גרשיים לועזיים בשאילתה לגרשיים עבריים בטקסט', () {
        // הטקסט מכיל ראשי תיבות עם ״ (U+05F4), השאילתה עם " רגיל.
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'רמב״ם אמר',
          query: 'רמב"ם',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), 'רמב״ם');
      });

      test('מדגיש ביטוי רב-מילים כשמופיע ברצף', () {
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'פתיח אבג דהו סוף',
          query: 'אבג דהו',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        final highlighted = _highlighted(spans);
        expect(highlighted, contains('אבג'));
        expect(highlighted, contains('דהו'));
      });

      test('ללא התאמה מחזיר את הטקסט כמות שהוא ללא הדגשה', () {
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'שלום עולם',
          query: 'ברכה',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), isEmpty);
        expect(_allText(spans), 'שלום עולם');
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  group('buildExcerptText', () {
    test('קטע של שתי שורות שומר את מעבר השורה', () {
      expect(
        SnippetBuilder.buildExcerptText(
          fullText: 'סוף השורה  \nתחילת הבאה',
          query: 'השורה',
          maxChars: 220,
        ),
        'סוף השורה\nתחילת הבאה',
      );
    });

    test('טקסט קצר מהמגבלה מוחזר כמות שהוא', () {
      expect(
        SnippetBuilder.buildExcerptText(
          fullText: 'טקסט קצר',
          query: 'קצר',
          maxChars: 220,
        ),
        'טקסט קצר',
      );
    });

    test(
      'חותך קטע סביב ההתאמה ומוסיף "..."',
      () {
        final fullText = '${'מילה ' * 60}מצרים ${'עוד ' * 60}';
        final excerpt = SnippetBuilder.buildExcerptText(
          fullText: fullText,
          query: 'מצרים',
          maxChars: 60,
        );

        expect(excerpt, contains('מצרים'));
        expect(excerpt, contains('...'));
        expect(excerpt.length, lessThan(fullText.length));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'ללא התאמה מחזיר את תחילת הטקסט עם "..."',
      () {
        final fullText = 'אבגד ' * 60;
        final excerpt = SnippetBuilder.buildExcerptText(
          fullText: fullText,
          query: 'מצרים',
          maxChars: 60,
        );

        expect(excerpt.trimRight(), endsWith('...'));
        expect(excerpt.length, lessThan(fullText.trim().length));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  group('htmlToPlainText - חילוץ טקסט גולמי', () {
    test('מסיר תגי הדגשה של המנוע ומנרמל רווחים', () {
      final plain = SnippetBuilder.htmlToPlainText(
        'בראשית <font color="red">ברא</font>   אלהים',
      );
      expect(plain, 'בראשית ברא אלהים');
    });

    test('שומר את מעבר השורה של קטע חוצה-שורות', () {
      final plain = SnippetBuilder.htmlToPlainText(
        'תהו <font color=red>ובהו</font><br> ויאמר אלהים',
      );
      expect(plain, 'תהו ובהו\nויאמר אלהים');
    });

    test('כיווץ הרווחים זהה לאלגוריתם הקודם בקלט אקראי (perf)', () {
      // הקודם, כלשונו: שתי סריקות RegExp בכל קטע, גם בלי סימון <br>.
      String oldCollapse(String text) => text
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(' ?\uE000 ?'), '\n');
      dom.Element? parseBody(String html) => html_parser
          .parse(
            html.replaceAll(
              RegExp(r'<br\s*/?>', caseSensitive: false),
              '\uE000',
            ),
          )
          .body;
      List<String> oldSpanTexts(String html) {
        final texts = <String>[];
        void walk(dom.Node node) {
          for (final child in node.nodes) {
            if (child is dom.Text) {
              final text = oldCollapse(child.text);
              if (text.isNotEmpty) texts.add(text);
            } else if (child is dom.Element) {
              walk(child);
            }
          }
        }

        final body = parseBody(html);
        if (body != null) walk(body);
        return texts.isEmpty ? [''] : texts;
      }

      const parts = [
        'ויאמר',
        ' ',
        '  ',
        '\n',
        '\t',
        '<br>',
        '<BR/>',
        '<br />',
        ' <br> ',
        '<b>משה</b>',
        '<font color="red">אל</font>',
        '&nbsp;',
        '\uE000',
      ];
      final random = Random(3);
      for (var i = 0; i < 500; i++) {
        final html = [
          for (var n = random.nextInt(8) + 1; n > 0; n--)
            parts[random.nextInt(parts.length)],
        ].join();
        expect(
          SnippetBuilder.htmlToPlainText(html),
          oldCollapse(parseBody(html)?.text ?? '').trim(),
          reason: html,
        );
        final spans = SnippetBuilder.fromHighlightedHtml(
          html: html,
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );
        expect(
          [for (final span in spans) (span as TextSpan).text],
          oldSpanTexts(html),
          reason: html,
        );
      }
    });
  });

  group('spansFromRanges - הדגשת חלק מטוקן בסרגל התוצאות', () {
    test('מדגיש רק את הטווח שהתקבל ולא את המילה השלמה', () {
      const text = 'דכוותי כוונתו';
      // "כוו" בתוך "דכוותי" (אופסט 1) ובתוך "כוונתו" (אופסט 7)
      final spans = SnippetBuilder.spansFromRanges(
        plainText: text,
        ranges: const [
          [1, 4],
          [7, 10],
        ],
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), 'כווכוו');
      expect(_allText(spans), text);
    });

    test('רשימת טווחים ריקה משאירה את הטקסט ללא הדגשה', () {
      final spans = SnippetBuilder.spansFromRanges(
        plainText: 'טקסט בלי התאמה',
        ranges: const [],
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );
      expect(_highlighted(spans), isEmpty);
      expect(_allText(spans), 'טקסט בלי התאמה');
    });

    test('מתעלם מטווח חורג מגבולות הטקסט', () {
      const text = 'קצר';
      final spans = SnippetBuilder.spansFromRanges(
        plainText: text,
        ranges: const [
          [0, 99],
        ],
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );
      expect(_allText(spans), text);
    });
  });
}
