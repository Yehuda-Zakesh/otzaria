import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/text_book/editing/services/markdown_processor.dart';
import 'package:otzaria/text_book/editing/services/preview_renderer.dart';

Widget _preview(String markdown) => MaterialApp(
  home: Scaffold(
    body: PreviewRenderer().renderPreview(
      markdown: markdown,
      textStyle: const TextStyle(fontSize: 18),
    ),
  ),
);

RichText _richTextOf(WidgetTester tester, String text) => tester
    .widgetList<RichText>(find.byType(RichText))
    .firstWhere((rich) => rich.text.toPlainText().contains(text));

void main() {
  testWidgets('בסיס rtl/justify נקבע בשורש בלבד ועובר בירושה', (tester) async {
    await tester.pumpWidget(_preview('<p><b>מודגש</b> ורגיל</p>'));
    await tester.pumpAndSettle();

    final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    final fragment = html_parser.parseFragment(html.html);
    final root = fragment.children.single;
    final paragraph = root.children.single;
    final bold = paragraph.children.single;
    expect(html.customStylesBuilder!(root), {
      'direction': 'rtl',
      'text-align': 'justify',
    });
    expect(html.customStylesBuilder!(paragraph), isNull);
    expect(html.customStylesBuilder!(bold), isNull);

    final rich = _richTextOf(tester, 'מודגש');
    expect(rich.textAlign, TextAlign.justify);
    expect(rich.textDirection, TextDirection.rtl);
  });

  testWidgets('קוד נשאר LTR, ובלוק בתוך קוד חוזר ל-RTL כמקודם', (tester) async {
    await tester.pumpWidget(
      _preview(
        '<p>פתיחה</p><pre><code>a = 1</code></pre><code><div>בפנים</div></code>',
      ),
    );
    await tester.pumpAndSettle();

    final code = _richTextOf(tester, 'a = 1');
    expect(code.textDirection, TextDirection.ltr);
    expect(code.textAlign, TextAlign.left);

    final nested = _richTextOf(tester, 'בפנים');
    expect(nested.textDirection, TextDirection.rtl);
    expect(nested.textAlign, TextAlign.justify);
  });

  test('מטמון ההמרה מחזיר לכל טקסט את ה-HTML שלו', () {
    const processor = MarkdownProcessor();
    MarkdownProcessor.clearCache();
    final first = processor.markdownToHtml('ראשון');
    final second = processor.markdownToHtml('שני');
    expect(first, contains('ראשון'));
    expect(second, contains('שני'));
    expect(processor.markdownToHtml('ראשון'), same(first));
  });

  test('לאלמנט בשורש הפרגמנט אין הורה — עליו נשען הבסיס של הסגנונות', () {
    final fragment = html_parser.parseFragment('<div><p>א</p></div>');
    final div = fragment.children.single;
    expect(div.parent, isNull);
    expect(div.children.single.parent, isA<dom.Element>());
  });
}
