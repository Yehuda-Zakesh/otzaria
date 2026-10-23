import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

import 'inline_parity_harness.dart';

// כל markup שמסלול הספאנים מקבל מוצג בדיוק כמו ב-HtmlWidget: גובה, שבירת
// שורות, מיקום כל תו, סגנון והתנהגות קישור לכל תו, טקסט להעתקה וסימונים מורמים.
const _long =
    'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר וַיְהִי אוֹר וַיַּרְא אֱלֹהִים אֶת הָאוֹר כִּי טוֹב';
const _taamim =
    'וַיִּקְרָ֨א אֱלֹהִ֤ים לָאוֹר֙ י֔וֹם וְלַחֹ֖שֶׁךְ קָ֣רָא לָ֑יְלָה וַֽיְהִי־עֶ֥רֶב';

String _anchor(
  int variant,
  String letter, {
  bool active = false,
  int ref = 0,
}) =>
    '<a class="link-anchor link-anchor-$variant${active ? ' link-anchor-active' : ''}" '
    'href="otzaria://anchor?ref=3_$ref">${wrapLinkAnchorLetter(letter, variant)}</a>';

String _spanAnchor(int variant, String letter) =>
    '<span class="link-anchor link-anchor-$variant">'
    '${wrapLinkAnchorLetter(letter, variant)}</span>';

final Map<String, List<String>> _cases = {
  'עוגני מפרשים': [
    'בראשית ${_anchor(0, 'א')} ברא ${_anchor(1, 'ב', ref: 1)} אלהים ${_anchor(2, 'ג', active: true, ref: 2)} את $_long ${_anchor(3, 'ד', ref: 3)}',
    for (var v = 0; v < kLinkAnchorVariants.length; v++)
      '$_long ${_anchor(v, 'יא', ref: v)} $_long',
    '$_taamim${_anchor(4, 'ה')}${_anchor(5, 'ו', ref: 1)} סוף',
    'פנל ${_spanAnchor(0, 'א')} ו${_spanAnchor(6, 'ב')} $_long',
  ],
  'טווח ציטוט וסמני הערות': [
    'לפני <a class="link-anchor-range" href="otzaria://anchor?ref=3_1&range=1">שמות כט מג</a> אחרי',
    'לפני <span class="link-anchor-range">טווח בפאנל</span> אחרי $_long',
    'טקסט <a class="numbered-note-marker" href="otzaria://note-marker?id=1"><span class="raised-sup">\u20679\u2069</span></a> המשך $_long',
    'טקסט <a class="numbered-note-marker" href="otzaria://note-marker?id=2">(9)</a> המשך',
    'מילה<a class="book-note-marker" href="otzaria://book-note?id=3">\u2067*\u2069</a> אחרי $_long',
    'הערה<span class="footnote-marker-number">\u20671\u2069</span> ושתיים<span class="raised-sup">\u2067א\u2069</span> $_long',
  ],
  'קישורים ישירים והערות אישיות': [
    'ראה <a href="otzaria://inline-link?path=%D7%90&index=2&ref=%D7%90" style="text-decoration: underline;">בראשית א א</a> ועוד $_long',
    '<a href="otzaria://note?line=4" style="text-decoration: underline; text-decoration-style: dotted; text-decoration-color: #1565c0; color: currentcolor;">$_long</a> סוף',
    'ראה <a href="otzaria://inline-link?path=x&index=1&ref=y" style="text-decoration: underline;">מקור</a> <a href="otzaria://note?line=0" style="text-decoration: underline; text-decoration-style: dotted; text-decoration-color: #1565c0; color: currentcolor;">והערה</a>${_anchor(0, 'א')}',
    'קישור חיצוני <a href="https://example.com">אתר</a> וקישור <a href="">ריק</a>',
    '<a>בלי href</a> ו<a href="x" data-ref="1" title="כותרת">עם data</a>',
  ],
  'עיצוב מיובא': [
    'טקסט <span style="color:#2828AC;">כחול</span> ו<span style="font-size:80%;">קטן</span> $_long',
    '<span style="font-size:120%; font-family: SBL Hebrew;">$_taamim</span> רגיל',
    '<span style="font-family: \'SBL Hebrew\', serif;">גופן</span> <span style="color:Gray;">אפור</span> <span style="color=#123456">שבור</span>',
    '<span style="color:#2828AC; font-size:92%; font-family:FONT1;">שלוש</span> <span style="background-color:#ffff00; color:#000000;">רקע</span>',
    '<span style="color: #ggg">hex פגום</span> <span style="color: #12">קצר</span> $_long',
    '<small style="color: gray;">(קטן אפור)</small> <b style="font-size:110%">מודגש גדול</b> $_long',
    '<span style="font-size:90%; font-weight: 600">משקל</span> <span style="font-weight:bold;">בולד</span> <span style="font-weight: normal">רגיל</span>',
    "<span style='font-size:92%'>גרש</span> <span class=\"H\">מחלקה</span> <span class=\"mediumGrey\">אחרת</span>",
    '<i data-overlay="x" data-value="y">נטוי עם data</i> <span dir="rtl">כיוון</span>',
    'א <u>קו</u> <s>מחוק</s> <del>נמחק</del> <ins>הוכנס</ins> <mark>סימון</mark> <em>הדגשה</em> <cite>ציטוט</cite>',
    '<span style="text-decoration: underline wavy #ff0000;">גלי</span> <span style="text-decoration-line: underline overline; text-decoration-thickness: 2px;">כפול</span>',
    '<span style="unicode-bidi: normal; direction: inherit; color: rgba(10, 20, 30, 1.000); text-decoration: underline; text-decoration-thickness: 2px; text-decoration-color: rgba(200, 0, 0, 1.000)">תוסף</span> $_long',
    '<span style="unicode-bidi: normal; direction: inherit; background-color: rgba(255, 200, 0, 1.000); text-decoration-line: underline overline; text-decoration-color: rgba(255, 200, 0, 1.000); text-decoration-thickness: 3px">נחשף</span>',
    '<span style="font-size: smaller">א</span><span style="font-size: larger">ב</span><span style="font-size: 1.5em">ג</span><span style="font-size: x-large">ד</span><span style="font-size: 12">ה</span>',
    '<span style="color: hsl(120, 100%, 25%)">ירוק</span> <span style="color: #f00a">שקוף</span> <span style="font-style: normal"><i>נטוי</i></span> <i><span style="font-style: normal">ישר</span></i>',
    '<u><span style="text-decoration: none">לא מוסר</span></u> <span style="text-decoration: underline"><span style="text-decoration-color: #00ff00">צבע</span></span>',
    '<span style="text-decoration: underline; text-decoration: line-through">קו מוחלף</span>',
    '<a href="https://example.com" style="text-decoration: line-through">קישור מחוק</a>',
    '<small><big>א</big></small> <big><big>ב</big></big> <span style="font-size:2em"><span style="font-size:smaller">ג</span><span style="font-size:x-small">ד</span></span>',
    '<B>רישיות</B> <SPAN STYLE="COLOR: RED; Font-Size: 1.2EM">תג</SPAN> <span style="text-decoration: underline; text-decoration-thickness: 200%;">עבה</span> <span style="text-decoration: line-through double;">כפול</span>',
  ],
  'הדגשות חיפוש בשורה מעוגנת': [
    'בראשית <span style="color: red">ברא</span>${_anchor(0, 'א')} אלהים <span style="background-color: rgba(255, 255, 0, 0.8); color: black">את</span> $_long',
    '<a href="otzaria://inline-link?path=x&index=1&ref=y" style="text-decoration: underline;">קישור <span style="color: blue; background-color: rgba(255, 255, 0, 0.8);">מודגש</span></a>${_anchor(1, 'ב')}',
    '<span style="color: red; ">שתי</span><span style="color: red">הדגשות</span> <span style="color: red"><span style="color: blue; background-color: rgba(255, 255, 0, 0.8);">מקוננות</span></span>',
  ],
  'רווחים וישויות': [
    '<small>(א) </small>ב <b> ג </b> ד  <i>ה</i>\n\tו',
    'א <br> ב<br>ג <br><br> ד',
    '<b>סוף </b>',
    ' <b> </b> התחלה <i></i> <i> </i>סוף <br>',
    'א&amp;ב &lt;ג&gt; &quot;ד&quot; &#1488; &#x5D0; &copy; &nbsp;ה&thinsp;ו',
    '<a class="link-anchor link-anchor-0" href="otzaria://anchor?ref=1_0">(א ב)</a> רווח בתוך nowrap',
    'סוגר יתום</span> ו</b> ו</a> אחרי',
    '<b>א<i>ב</b>ג</i>ד',
    '<a href="x">א<a href="y">ב</a></a>',
    '<span class="x">א </span>ב <span>ג  </span> ד <span dir="rtl"> ה </span> ו',
    '<a href="x">קישור </a>אחרי <a class="link-anchor-range" href="y"> טווח </a> סוף',
    'א <!-- הערה --> ב<!--x-->ג <span style="white-space: nowrap"> ד ה  ו	ז </span>ח',
    '<br>א <b><br> ב</b> ג<br><b> ד</b> &#160;ה&#x200F; &apos;ו&apos;<br>',
  ],
  'כותרות': [
    '<h2>כותרת ${_anchor(0, 'א')} עם עוגן</h2>',
    '<h3>כותרת <span style="color:#2828AC;">צבעונית</span></h3>',
    ' <h1><a href="otzaria://inline-link?path=x&index=1&ref=y">קישור בכותרת</a></h1> ',
    // מילות גודל מוחלטות יחסיות לשורש של HtmlWidget, לא לכותרת.
    '<h2>א<span style="font-size: medium">ב</span><span style="font-size: x-large">ג</span></h2>',
    '<h5>קטנה <big>גדולה</big> <span style="font-size: small">קטן</span></h5>',
  ],
};

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File('fonts/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('TaameyDavidCLM', ['TaameyDavidCLM-Medium.ttf']);
    await _loadFont('FrankRuhlCLM', [
      'FrankRuehlCLM-Medium.ttf',
      'FrankRuehlCLM-Bold.ttf',
    ]);
    await _loadFont('Rubik', ['Rubik-VariableFont_wght.ttf']);
    await _loadFont('NotoRashiHebrew', [
      'NotoRashiHebrew-VariableFont_wght.ttf',
    ]);
  });

  _cases.forEach((group, lines) {
    testWidgets('זהות ל-HtmlWidget: $group', (tester) async {
      for (final theme in [parityTheme, parityGreyTheme]) {
        for (final html in lines) {
          await expectInlineParity(tester, html, theme: theme);
        }
      }
    });
  });

  testWidgets('זהות בהגדרות שונות: בולד, בלי יישור, בלי ניקוד, רוחבים', (
    tester,
  ) async {
    final html = _cases['עוגני מפרשים']!.first;
    for (final settings in const [
      RenderSettings(
        fontSize: 18,
        lineHeight: 1.5,
        fontWeight: FontWeight.bold,
      ),
      RenderSettings(fontSize: 22, lineHeight: 1.8, justifyText: false),
      RenderSettings(fontSize: 20, lineHeight: 1.6, removeNikud: true),
      RenderSettings(fontSize: 26, lineHeight: 1.4, fontFamily: 'Rubik'),
      RenderSettings(fontSize: 20, lineHeight: 1.6, fontFamily: 'FrankRuhlCLM'),
    ]) {
      for (final width in const [180.0, 320.0, 611.0]) {
        await expectInlineParity(
          tester,
          html,
          settings: settings,
          width: width,
        );
      }
    }
  });

  testWidgets('זהות בלי callbacks', (tester) async {
    for (final html in _cases['קישורים ישירים והערות אישיות']!) {
      await expectInlineParity(tester, html, withCallbacks: false);
    }
  });

  // גופנים אמיתיים: עיצוב עברי עם ניקוד וטעמים, רוחבי גליפים אמיתיים ו-justify.
  for (final family in const ['TaameyDavidCLM', 'FrankRuhlCLM', 'Rubik']) {
    testWidgets('זהות בגופן אמיתי: $family', (tester) async {
      for (final lines in _cases.values) {
        for (final html in lines) {
          for (final width in const [240.0, 433.0]) {
            await expectInlineParity(
              tester,
              html,
              width: width,
              settings: RenderSettings(
                fontSize: 21,
                lineHeight: 1.6,
                fontFamily: family,
              ),
            );
          }
        }
      }
    });
  }
}
