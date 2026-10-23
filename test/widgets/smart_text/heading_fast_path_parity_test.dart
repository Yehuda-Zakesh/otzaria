import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// שורת כותרת שלמה עוברת למסלול המהיר; היא חייבת להיראות בדיוק כמו ב-HtmlWidget.
// הייחוס הוא אותו HTML כשהוא מוצג בכפייה ב-HtmlWidget.
const _needle = 'כותרת';

class _Rendered {
  final Rect root;
  final Rect paragraph;
  final List<(double, double, double, double)> lines;
  final TextStyle style;

  _Rendered(this.root, this.paragraph, this.lines, this.style);
}

Future<_Rendered> _render(
  WidgetTester tester,
  String html,
  RenderSettings settings, {
  required bool expectHtmlWidget,
  bool forceHtmlWidget = false,
}) async {
  final key = GlobalKey();
  // הייחוס: אותו HTML מוצג ב-HtmlWidget.
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
              width: 300,
              child: SelectionArea(
                child: SmartTextWidget(
                  key: key,
                  text: html,
                  settings: settings,
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

  final paragraphFinder = find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(_needle),
    ),
  );
  final richText = tester.widget<RichText>(paragraphFinder);
  final render = tester.renderObject<RenderParagraph>(paragraphFinder);
  TextStyle? style;
  void visit(InlineSpan span, TextStyle inherited) {
    if (style != null || span is! TextSpan) return;
    final merged = span.style == null ? inherited : inherited.merge(span.style);
    if (span.text?.contains(_needle) ?? false) {
      style = merged;
      return;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, merged);
    }
  }

  visit(richText.text, const TextStyle());
  return _Rendered(
    tester.getRect(find.byKey(key)),
    tester.getRect(paragraphFinder),
    [
      for (final box in render.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: richText.text.toPlainText().length,
        ),
      ))
        (box.left, box.top, box.right, box.bottom),
    ],
    style!,
  );
}

void main() {
  const fonts = ['FrankRuhlCLM', 'TaameyDavidCLM', 'Rubik'];
  const bodies = [
    _needle,
    '$_needle <b>מודגש</b> <small>(קטן)</small>',
    '$_needle ארוכה מאוד שנשברת לכמה שורות בתוך רוחב צר של שלוש מאות פיקסלים',
  ];

  for (var level = 1; level <= 6; level++) {
    for (final font in fonts) {
      for (final weight in const [null, FontWeight.bold]) {
        testWidgets('h$level $font weight=$weight — זהה ל-HtmlWidget', (
          tester,
        ) async {
          final settings = RenderSettings(
            fontSize: 20,
            fontFamily: font,
            fontWeight: weight,
            lineHeight: 1.6,
          );
          for (final body in bodies) {
            final fast = await _render(
              tester,
              '<h$level>$body</h$level>',
              settings,
              expectHtmlWidget: false,
            );
            final reference = await _render(
              tester,
              '<h$level>$body</h$level>',
              settings,
              expectHtmlWidget: true,
              forceHtmlWidget: true,
            );
            final reason = 'h$level/$font/$body';
            expect(fast.root, reference.root, reason: reason);
            expect(fast.paragraph, reference.paragraph, reason: reason);
            expect(fast.lines, reference.lines, reason: reason);
            expect(fast.style.fontSize, reference.style.fontSize);
            expect(fast.style.fontWeight, reference.style.fontWeight);
            expect(fast.style.fontVariations, reference.style.fontVariations);
            expect(fast.style.fontFamily, reference.style.fontFamily);
            expect(fast.style.height, reference.style.height);
          }
        });
      }
    }
  }

  testWidgets('טקסט לפני/אחרי הכותרת או שתי כותרות — נשאר ב-HtmlWidget', (
    tester,
  ) async {
    const settings = RenderSettings(fontSize: 20);
    for (final html in const [
      'לפני<h2>$_needle</h2>',
      '<h2>$_needle</h2>אחרי',
      '<h2>$_needle</h2><h3>שנייה</h3>',
      '<h2 class="x">$_needle</h2>',
    ]) {
      await _render(tester, html, settings, expectHtmlWidget: true);
    }
  });
}
