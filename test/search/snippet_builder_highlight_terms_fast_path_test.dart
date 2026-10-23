import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/search/utils/snippet_builder.dart';

/// המונחים כפי שמפרסר ה-HTML מחלץ אותם — הייחוס למסלול המהיר.
Set<String> _parsedTerms(String html) {
  final terms = <String>{};
  void walk(dom.Node node, bool highlighted) {
    for (final child in node.nodes) {
      if (child is dom.Text) {
        if (!highlighted) continue;
        final text = child.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isNotEmpty) terms.add(text);
      } else if (child is dom.Element) {
        walk(child, highlighted || {'font', 'mark'}.contains(child.localName));
      }
    }
  }

  walk(html_parser.parse(html).body!, false);
  return terms;
}

const _filler = 'ויאמר משה אל העם לאמר דברים רבים נאמרו שם ';

void main() {
  group('extractHighlightedTerms — קטע מנוע נקרא בלי מפרסר ה-HTML', () {
    test('קטעים בצורה שהמנוע מפיק נקראים במסלול המהיר', () {
      for (final html in [
        '$_filler<font color=red>שלום</font> $_filler',
        '<font color=red>א</font> ב <font color=red>ג</font>',
        'שורה<br>שנייה <font color=red>רש&quot;י</font> ו&#x27;',
        'בלי הדגשה כלל &amp; &lt;b&gt;',
        '<mark>שבתות</mark>',
      ]) {
        expect(SnippetBuilder.simpleHighlightedTerms(html), isNotNull);
      }
    });

    test('המסלול המהיר זהה למפרסר, וקלט אחר נופל אליו', () {
      final cases = [
        '$_filler<font color=red>שלום</font> $_filler<font color=red>השלום</font>',
        '<font color=red>ברא</font> שוב <font color=red>ברא</font>',
        '<FONT color=red>גדול</FONT> <Mark>קטן</Mark>',
        '<font color=red>אבג \n\t  דהו</font>',
        '<font color=red>   </font><font color=red></font>',
        '<font color=red>רמב&quot;ם</font> <font color=red>a&amp;lt;b</font>',
        '<font color=red>&lt;x&gt; &#x27;</font>',
        '<font color=red>&nbsp;שם</font>',
        '<font color=red>&AMP;</font> <font color=red>&#39;</font>',
        '<font color="red">מצוטט</font>',
        '<font title=">">מירכאות</font>',
        '<font color=red>א<b>ב</b>ג</font>',
        '<font color=red>פתוח',
        '<font color=red>א</mark>',
        '<b>כותרת</b> <font color=red>מצא</font>',
        '<!-- <font color=red>הערה</font> --> טקסט',
        '<script><font color=red>קוד</font></script>',
        '<textarea><font color=red>שדה</font></textarea>',
        '<select><font color=red>בחירה</font></select>',
        '<table><font color=red>טבלה</font></table>',
        '<font-x>לא</font-x> <fontx>לא</fontx>',
        '<fontx>לא</font> <marker>לא</mark>',
        'שורה<br/>ו<BR >ו<br ><font color=red>מילה</font>',
        '<font color=red>\u0000אפס</font>',
        '<font color=red>\r\nשורות\r</font>',
        '<font/>סגור</font>',
        '',
      ];
      for (final html in cases) {
        final fast = SnippetBuilder.simpleHighlightedTerms(html);
        final parsed = _parsedTerms(html);
        if (fast != null) {
          expect(fast.toList(), parsed.toList(), reason: html);
        }
        expect(
          SnippetBuilder.extractHighlightedTerms(html).toList(),
          parsed.toList(),
          reason: html,
        );
      }
    });

    test('צירופים אקראיים של קטעים — אותם מונחים ובאותו סדר', () {
      const pieces = [
        'טקסט ',
        ' ',
        '\n',
        '<br>',
        '<BR/>',
        '<font color=red>',
        '<mark>',
        '</font>',
        '</mark>',
        'שלום',
        '&quot;',
        '&amp;',
        '&#x27;',
        '&lt;',
        '&nbsp;',
        '&',
        '<b>',
        '</b>',
        '<font color="red">',
        '<!--',
        '-->',
        '<',
        '>',
      ];
      final random = Random(7);
      for (var i = 0; i < 3000; i++) {
        final html = List.generate(
          random.nextInt(12),
          (_) => pieces[random.nextInt(pieces.length)],
        ).join();
        final fast = SnippetBuilder.simpleHighlightedTerms(html);
        if (fast != null) {
          expect(fast.toList(), _parsedTerms(html).toList(), reason: html);
        }
      }
    });
  });
}
