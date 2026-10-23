import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// markup שאינו מצייר דבר (עוגני מפרשים ריקים, spans של mam) וישויות רווח
// נשארים במסלול המהיר, ומוצגים בדיוק כמו ב-HtmlWidget. הייחוס הוא markup
// שקול בפרסור HTML, מוצג בכפייה ב-HtmlWidget.
class _Rendered {
  final String text;
  final Rect root;
  final List<Rect> paragraphs;
  final List<TextBox> boxes;

  _Rendered(this.text, this.root, this.paragraphs, this.boxes);
}

Future<_Rendered> _render(
  WidgetTester tester,
  String html, {
  required bool expectHtmlWidget,
  bool forceHtmlWidget = false,
}) async {
  final key = GlobalKey();
  // הייחוס: ה-HTML מוצג ב-HtmlWidget.
  SmartTextWidget.debugForceHtmlWidget = forceHtmlWidget;
  addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 240,
              child: SelectionArea(
                child: SmartTextWidget(
                  key: key,
                  text: html,
                  settings: const RenderSettings(fontSize: 20, lineHeight: 1.6),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  SmartTextWidget.debugForceHtmlWidget = false;
  expect(
    find.byType(HtmlWidget),
    expectHtmlWidget ? findsOneWidget : findsNothing,
    reason: html,
  );

  final paragraphs = find
      .descendant(
        of: find.byKey(key),
        matching: find.byWidgetPredicate((w) => w is RichText),
      )
      .evaluate()
      .toList();
  final text = StringBuffer();
  final boxes = <TextBox>[];
  for (final element in paragraphs) {
    final plain = (element.widget as RichText).text.toPlainText();
    text.write(plain);
    boxes.addAll(
      (element.renderObject! as RenderParagraph).getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length),
      ),
    );
  }
  return _Rendered(
    text.toString(),
    tester.getRect(find.byKey(key)),
    [
      for (final element in paragraphs)
        tester.getRect(find.byWidget(element.widget)),
    ],
    boxes,
  );
}

Future<void> _expectParity(
  WidgetTester tester,
  String fastHtml,
  String referenceHtml,
) async {
  final fast = await _render(tester, fastHtml, expectHtmlWidget: false);
  final reference = await _render(
    tester,
    referenceHtml,
    expectHtmlWidget: true,
    forceHtmlWidget: true,
  );
  expect(fast.text, reference.text, reason: fastHtml);
  expect(fast.root, reference.root, reason: fastHtml);
  expect(fast.paragraphs, reference.paragraphs, reason: fastHtml);
  expect(fast.boxes, reference.boxes, reason: fastHtml);
}

void main() {
  const long = 'שורה ארוכה שנשברת לכמה שורות ברוחב הצר של הבדיקה הזאת';

  group('עוגני מפרשים ריקים', () {
    const anchors = [
      '<i data-commentator="Magen Avraham" data-order="3"></i>',
      '<i data-commentator="Mishnah Berurah" data-label="א"></i>',
      '<i data-commentator="Be\'er HaGolah" data-label="ב" data-order="12"></i>',
      '<i data-commentator="Ateret Zekenim" data-label="♦" data-order="1"></i>',
    ];
    String reference(String anchor) => anchor.replaceFirst('"></i>', '" ></i>');

    testWidgets('זהה ל-HtmlWidget', (tester) async {
      for (final anchor in anchors) {
        for (final body in [
          'לפני $anchor אחרי',
          '$anchor פתיחה',
          'סוף $anchor',
          'צמוד$anchor$anchorלמילה',
          '<b>מודגש $anchor</b> $anchor <small>(קטן)</small>',
          '$long $anchor $long',
          '<h2>כותרת $anchor</h2>',
        ]) {
          await _expectParity(
            tester,
            body,
            body.replaceAll(anchor, reference(anchor)),
          );
        }
      }
    });

    testWidgets('עוגן עם תוכן או בלי מירכאות — זהה ל-HtmlWidget', (
      tester,
    ) async {
      for (final html in const [
        'א <i data-commentator="Magen Avraham">ב</i> ג',
        'א <i data-commentator=Mishnah Berurah" data-label="א"></i> ג',
        'א <i class="x"></i> ג',
      ]) {
        await _expectParity(tester, html, html);
      }
    });
  });

  group('spans של mam', () {
    const classes = [
      'mam-spi-samekh',
      'mam-spi-pe',
      'mam-kq',
      'mam-kq-k',
      'mam-kq-q',
      'mam-kq-trivial',
      'mam-implicit-maqaf',
      'mam-spi-invnun',
    ];

    testWidgets('זהה ל-HtmlWidget', (tester) async {
      for (final cls in classes) {
        final open = '<span class="$cls">';
        for (final body in [
          'לפני $open{פ}</span> אחרי',
          '$open<span class="mam-kq-k">(כתיב)</span> <span class="mam-kq-q">[קרי]</span></span> המשך',
          '<b>$open מודגש</span></b>',
          '$long $openבאמצע</span> $long',
        ]) {
          await _expectParity(
            tester,
            body,
            body.replaceAll('">', '" >'),
          );
        }
      }
    });

    testWidgets('mam עם class נוסף — זהה ל-HtmlWidget', (tester) async {
      const html = 'א <span class="mam-kq x">ב</span> ג';
      await _expectParity(tester, html, html);
    });
  });

  group('ישויות רווח', () {
    testWidgets('&nbsp; ו-&thinsp; זהים ל-HtmlWidget ואינם מתכווצים', (
      tester,
    ) async {
      for (final body in [
        'א&nbsp;ב',
        'א&nbsp;&nbsp;&nbsp;ב',
        '&nbsp;פתיחה',
        'סוף&nbsp;',
        'א &nbsp; ב',
        'א&thinsp;ב&thinsp;&thinsp;ג',
        '&thinsp;פתיחה סוף&thinsp;',
        '<b>א&nbsp;</b>&nbsp;<small>ב</small>',
        'א&nbsp;<br>&nbsp;ב',
        long.replaceAll(' ', '&nbsp;'),
        '<h3>&nbsp;כותרת&thinsp;</h3>',
      ]) {
        await _expectParity(
          tester,
          body,
          body.replaceAll('&nbsp;', '&#160;').replaceAll('&thinsp;', '&#8201;'),
        );
      }
    });

    testWidgets('NBSP גולמי אינו מתכווץ — כמו ב-HtmlWidget', (tester) async {
      for (final body in ['א  ב', ' פתיחה', 'א   ב']) {
        await _expectParity(tester, body, body.replaceAll(' ', '&#160;'));
      }
    });

    testWidgets('ישות אחרת — זהה ל-HtmlWidget', (tester) async {
      for (final html in const ['א&amp;nbsp;ב', 'א&lt;ב&gt; &#1488;']) {
        await _expectParity(tester, html, html);
      }
    });
  });
}
