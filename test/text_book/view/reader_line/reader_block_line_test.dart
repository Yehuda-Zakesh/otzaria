import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';

// התבנית שקבעה עד כה אם שורה היא בלוק — ההשוואה מולה מוכיחה התנהגות זהה.
final RegExp _referenceBlockMarkup = RegExp(
  r'<(?:details|table|img|ul|ol|pre|blockquote|hr|h[1-6])\b',
  caseSensitive: false,
);
final RegExp _referenceLeadingBlock = RegExp(
  r'^\s*<(?:div|p|center|li)\b',
  caseSensitive: false,
);

void main() {
  test('שורת טקסט עם תגיות שאינן בלוק לא מריצה את תבנית הבלוק', () {
    debugReaderBlockMarkupChecks = 0;
    final line = List.filled(
      50,
      '<small>(א)</small> <span class="x">מילה</span> <sup>ב</sup> מילה',
    ).join(' ');

    expect(isReaderBlockLine(line), isFalse);
    expect(debugReaderBlockMarkupChecks, 0);
  });

  test('התבנית נבדקת רק במיקומי תג שעשוי להיות בלוק', () {
    debugReaderBlockMarkupChecks = 0;

    expect(isReaderBlockLine('<b>א</b> <small>ב</small> <i>ג</i>'), isFalse);
    expect(debugReaderBlockMarkupChecks, 2);
  });

  test('זיהוי שורת בלוק זהה לתבנית המקורית', () {
    const lines = [
      '',
      '<',
      'טקסט <',
      'טקסט בלי תגיות',
      '<b>מודגש</b> ורגיל',
      '<br>שורה<br/>',
      '<bold>לא תג בלוק</bold>',
      '<i>נטוי</i> <img src="a.png">',
      '<IMG SRC="a.png">',
      'לפני <Table><tr><td>א</td></tr></Table>',
      '<details><summary>א</summary>ב</details>',
      'א <hr/> ב',
      'א <HR> ב',
      'א <hra> ב',
      '<h2>כותרת</h2>',
      'טקסט <H6>כותרת</H6>',
      'טקסט <h7>לא כותרת</h7>',
      '<ul><li>א</li></ul>',
      'א <OL> ב',
      '<pre>קוד</pre>',
      '<blockquote>ציטוט</blockquote>',
      '<blockquotes>לא</blockquotes>',
      '<tablet>לא</tablet>',
      '<u>קו תחתון</u> <p>פסקה</p>',
      '  <div style="x">א</div>',
      '<li>א</li>',
      '<center>א</center>',
      '<<img>',
      '<@img> <`img>',
      'א <İMG> ב',
      '<H2',
      '<Div>א</Div>',
      'טקסט <Blockquote cite="x">',
      'טקסט <img',
      'סוף <h',
      'א < ב > ג <Table',
      '&lt;img&gt; &amp; <b',
      '<br><BR/><b>א',
      '<!-- <hr> -->',
    ];
    for (final line in lines) {
      final expected =
          line.contains('<') &&
          (_referenceBlockMarkup.hasMatch(line) ||
              _referenceLeadingBlock.hasMatch(line));
      expect(isReaderBlockLine(line), expected, reason: line);
    }
  });
}
