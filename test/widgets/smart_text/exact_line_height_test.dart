import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/widgets/smart_text/exact_line_height.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// גופני האפליקציה נטענים מהדיסק: מטריקות ה-ascent/descent האמיתיות שלהם הן
/// כל הסיפור כאן, וגופן הבדיקה של flutter_test אינו מייצג אותן.
const _fontFiles = {
  'FrankRuhlCLM': 'fonts/FrankRuehlCLM-Medium.ttf',
  'TaameyDavidCLM': 'fonts/TaameyDavidCLM-Medium.ttf',
  'KeterYG': 'fonts/KeterYG-Medium.ttf',
  'Tinos': 'fonts/Tinos-Regular.ttf',
  // עומד כאן במקום גופן ה-fallback של המערכת, שאליו נופלות ספרות superscript
  // (אין להן גליף באף גופן עברי באפליקציה).
  'Rubik': 'fonts/Rubik-VariableFont_wght.ttf',
};

Future<void> _loadFonts() async {
  for (final entry in _fontFiles.entries) {
    final bytes = await File(entry.value).readAsBytes();
    await (FontLoader(
      entry.key,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }
}

double _paragraphHeight(InlineSpan span, {StrutStyle? strutStyle}) {
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.rtl,
    strutStyle: strutStyle,
  )..layout(maxWidth: 2000);
  final height = painter.height;
  painter.dispose();
  return height;
}

TextSpan _plain(TextStyle base) =>
    TextSpan(text: 'ויאמר משה אל העם', style: base);

/// שורה שבתוכה ריצה בגופן אחר — כמו סימון הערה שנפתר לגופן מערכת.
TextSpan _withForeignRun(TextStyle base) => TextSpan(
  style: base,
  children: const [
    TextSpan(text: 'ויאמר משה '),
    TextSpan(
      text: '1',
      style: TextStyle(fontFamily: 'Rubik'),
    ),
    TextSpan(text: ' אל העם'),
  ],
);

TextSpan _withSuperscriptRun(TextStyle base) =>
    TextSpan(text: 'ויאמר ¹² אל העם', style: base);

/// שורה שבתוכה מילה ב-`<big>` — הסימון "גמ׳" בתלמוד.
TextSpan _withBigRun(TextStyle base) => TextSpan(
  style: base,
  children: [
    TextSpan(
      text: 'גמ׳ ',
      style: TextStyle(fontSize: base.fontSize! * kHtmlLargerFontScale),
    ),
    const TextSpan(text: 'תנא היכא קאי'),
  ],
);

Widget _wrap(Widget child) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(_loadFonts);

  group('exactLineHeightStrut', () {
    test('בלי קיבוע — ריצה בגופן אחר מגדילה את גובה השורה', () {
      const base = TextStyle(
        fontFamily: 'TaameyDavidCLM',
        fontSize: 18,
        height: 1.5,
      );
      expect(
        _paragraphHeight(_withForeignRun(base)),
        greaterThan(_paragraphHeight(_plain(base))),
      );
    });

    test('ספרות עיליות נשארות בגובה שורה קבוע', () {
      for (final family in _fontFiles.keys) {
        final base = TextStyle(fontFamily: family, fontSize: 18, height: 1.5);
        final content = _withSuperscriptRun(base);
        final strutStyle = exactLineHeightStrut(base, content);
        expect(strutStyle, isNotNull, reason: family);
        expect(
          _paragraphHeight(content, strutStyle: strutStyle),
          _paragraphHeight(_plain(base)),
          reason: family,
        );
      }
    });

    test('עם קיבוע — גובה השורה זהה לשורה שכולה בגופן הבסיס', () {
      for (final family in _fontFiles.keys) {
        for (final fontSize in [16.0, 18.0, 22.0]) {
          for (final lineHeight in [1.0, 1.5, 2.2]) {
            final base = TextStyle(
              fontFamily: family,
              fontSize: fontSize,
              height: lineHeight,
            );
            final content = _withForeignRun(base);
            final strutStyle = exactLineHeightStrut(base, content);
            expect(strutStyle, isNotNull);
            expect(
              _paragraphHeight(content, strutStyle: strutStyle),
              _paragraphHeight(_plain(base)),
              reason: '$family $fontSize/$lineHeight',
            );
          }
        }
      }
    });

    // הסימון "גמ׳" בתלמוד הוא <big><strong>, ולכן השורה שבה הוא יושב גבוהה
    // מהשורות סביבה — זו הדוגמה שהמשתמש דיווח עליה.
    test('מילה ב-<big> נכנסת לתיבת השורה — מקובעת לגובה הרגיל', () {
      for (final family in _fontFiles.keys) {
        final base = TextStyle(fontFamily: family, fontSize: 18, height: 1.5);
        final withBig = _withBigRun(base);
        expect(
          _paragraphHeight(withBig),
          greaterThan(_paragraphHeight(_plain(base))),
          reason: family,
        );
        expect(
          _paragraphHeight(
            withBig,
            strutStyle: exactLineHeightStrut(base, withBig),
          ),
          _paragraphHeight(_plain(base)),
          reason: family,
        );
      }
    });

    test('ריצה גדולה מ-<big> אינה מקובעת — כותרת בשורה צריכה מקום', () {
      const base = TextStyle(
        fontFamily: 'FrankRuhlCLM',
        fontSize: 18,
        height: 1.5,
      );
      final withHuge = TextSpan(
        style: base,
        children: const [
          TextSpan(text: 'כותרת', style: TextStyle(fontSize: 36)),
          TextSpan(text: ' והמשך'),
        ],
      );
      expect(exactLineHeightStrut(base, withHuge), isNull);
    });

    // במרווח צפוף אין בתיבת השורה מקום לגליפים של ריצה מוגדלת, וקיבוע היה
    // מפיל אותם על השורה שמעליה (נמדד: חפיפה של 1–3px במרווח 1.0–1.1).
    test('<big> אינו מקובע כשמרווח השורות צפוף מהגדלת הגופן', () {
      for (final lineHeight in [1.0, 1.1]) {
        final base = TextStyle(
          fontFamily: 'FrankRuhlCLM',
          fontSize: 18,
          height: lineHeight,
        );
        expect(
          exactLineHeightStrut(base, _withBigRun(base)),
          isNull,
          reason: 'מרווח $lineHeight',
        );
      }
    });

    // רגרסיה: TextSpan.visitChildren מדלג על ספאן בלי text, ולכן בדיקת הגדלים
    // חייבת לרדת בעץ בעצמה — אחרת ספאן-אב שנושא את הגופן הגדול חומק ממנה.
    test('גופן גדול על ספאן-אב (בלי text משלו) נתפס', () {
      const base = TextStyle(
        fontFamily: 'FrankRuhlCLM',
        fontSize: 18,
        height: 1.5,
      );
      final nested = TextSpan(
        style: base,
        children: const [
          TextSpan(
            style: TextStyle(fontSize: 54),
            children: [TextSpan(text: 'כותרת ענקית')],
          ),
        ],
      );
      expect(exactLineHeightStrut(base, nested), isNull);
    });

    test('ווידג\'ט inline אינו מקובע', () {
      const base = TextStyle(
        fontFamily: 'FrankRuhlCLM',
        fontSize: 18,
        height: 1.5,
      );
      final withWidget = TextSpan(
        style: base,
        children: const [
          TextSpan(text: 'ויאמר '),
          WidgetSpan(child: SizedBox(width: 10, height: 40)),
        ],
      );
      expect(exactLineHeightStrut(base, withWidget), isNull);
    });

    test('בלי גודל גופן או גובה שורה אין מה לקבע', () {
      const noSize = TextStyle(fontFamily: 'FrankRuhlCLM', height: 1.5);
      const noHeight = TextStyle(fontFamily: 'FrankRuhlCLM', fontSize: 18);
      expect(exactLineHeightStrut(noSize, _plain(noSize)), isNull);
      expect(exactLineHeightStrut(noHeight, _plain(noHeight)), isNull);
    });
  });

  group('מסלולי הרינדור מקבעים את גובה השורה', () {
    testWidgets('המסלול המהיר של SmartTextWidget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: 'ויאמר משה אל העם',
            settings: RenderSettings(
              fontSize: 18,
              fontFamily: 'FrankRuhlCLM',
              lineHeight: 1.5,
            ),
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.strutStyle?.forceStrutHeight, isTrue);
    });

    testWidgets('מסלול ה-HtmlWidget', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SmartTextWidget(
            text: 'טקסט <span class="link-anchor">א</span> ועוד',
            settings: RenderSettings(
              fontSize: 18,
              fontFamily: 'FrankRuhlCLM',
              lineHeight: 1.5,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HtmlWidget), findsOneWidget);
      final richText = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((widget) => widget.text.toPlainText().contains('ועוד'));
      expect(richText.strutStyle?.forceStrutHeight, isTrue);
    });

    // רגרסיה מקצה לקצה על צורת הטקסט בתלמוד, בשני המסלולים: `<big><strong>`
    // לבדו נשאר במסלול המהיר, ותוספת סמן-עוגן מעבירה את השורה ל-HtmlWidget.
    for (final withAnchor in [false, true]) {
      final anchor = withAnchor ? ' <span class="link-anchor">א</span>' : '';
      testWidgets(
        'שורת "גמ׳" בגובה של שורה רגילה'
        '${withAnchor ? ' (מסלול HtmlWidget)' : ''}',
        (tester) async {
          const settings = RenderSettings(
            fontSize: 18,
            fontFamily: 'FrankRuhlCLM',
            lineHeight: 1.5,
          );
          await tester.pumpWidget(
            _wrap(
              SizedBox(
                width: 600,
                child: Column(
                  children: [
                    SmartTextWidget(
                      text:
                          '<big><strong>גמ׳</strong></big> תנא היכא קאי$anchor',
                      settings: settings,
                    ),
                    SmartTextWidget(
                      text: 'תנא היכא קאי$anchor',
                      settings: settings,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(HtmlWidget),
            withAnchor ? findsNWidgets(2) : findsNothing,
          );
          final heights = tester
              .widgetList<RichText>(find.byType(RichText))
              .where((widget) => widget.text.toPlainText().contains('היכא'))
              .map((widget) => tester.getSize(find.byWidget(widget)).height)
              .toList();
          expect(heights, hasLength(2));
          expect(heights.first, heights.last);
        },
      );
    }

    testWidgets('פסקה במצב קריאה רציפה', (tester) async {
      const base = TextStyle(
        fontFamily: 'FrankRuhlCLM',
        fontSize: 18,
        height: 1.5,
      );
      await tester.pumpWidget(
        _wrap(
          ContinuousReadingParagraph(
            lines: const [
              ContinuousReadingParagraphLine(
                lineIndex: 0,
                text: 'ויאמר משה אל העם',
                htmlText: 'ויאמר משה אל העם',
                style: base,
              ),
            ],
            baseStyle: base,
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText));
      expect(richText.strutStyle?.forceStrutHeight, isTrue);
    });

    testWidgets('פסקה רציפה עם סימון גמ׳ — גובה הפסקה כפולה של גובה השורה', (
      tester,
    ) async {
      const base = TextStyle(
        fontFamily: 'FrankRuhlCLM',
        fontSize: 18,
        height: 1.5,
      );
      const html =
          '<big><strong>גמ׳</strong></big> תנא היכא קאי דקתני מאימתי '
          'ותו מאי שנא דתני בערבית ברישא לתני בשחרית ברישא';
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 240,
            child: ContinuousReadingParagraph(
              lines: const [
                ContinuousReadingParagraphLine(
                  lineIndex: 0,
                  text: html,
                  htmlText: html,
                  style: base,
                ),
              ],
              baseStyle: base,
            ),
          ),
        ),
      );

      // גובה השורה הנקייה כפי שהמנוע מעגל אותו — ולא 18×1.5 — כדי שהבדיקה
      // תמדוד אחידות ולא תיפול על עיגול לפיקסל שלם.
      final lineBox = _paragraphHeight(_plain(base));
      final height = tester.getSize(find.byType(RichText)).height;
      expect(height, greaterThan(lineBox));
      expect(height % lineBox, 0);
    });
  });
}
