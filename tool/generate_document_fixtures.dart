// ignore_for_file: avoid_print
//
// מחולל קורפוס קבצי-בדיקה לפורמטי המסמכים הנתמכים באוצריא.
//
// הפעלה:  dart run tool/generate_document_fixtures.dart <תיקיית-יעד>
//
// למה בדארט ולא בסקריפט חיצוני: הפורמטים הבינאריים (CFB של .doc, FIB,
// piece table) חייבים להיבנות *נכון* — קובץ שרק נראה כמו OLE אך אינו מכיל
// מבנה אמיתי אינו בודק דבר, והממיר דוחה אותו בצדק. הבנייה כאן משתמשת
// באותם מבנים שמתועדים ב-`docs/legacy_word_doc_research.md`.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'src/document_fixtures/ooxml_builder.dart';
import 'src/document_fixtures/word_binary_builder.dart';

/// PNG 1x1 — התוכן הקטן ביותר שהממירים מזהים כתמונה.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main(List<String> args) {
  if (args.isEmpty) {
    print('שימוש: dart run tool/generate_document_fixtures.dart <תיקייה>');
    exit(64);
  }
  final dir = Directory(args.first)..createSync(recursive: true);
  final corpus = buildFixtureCorpus();

  for (final name in corpus.keys.toList()..sort()) {
    File(
      '${dir.path}${Platform.pathSeparator}$name',
    ).writeAsBytesSync(corpus[name]!);
    print('${name.padRight(22)} ${corpus[name]!.length} bytes');
  }
  print('');
  print('נכתבו ${corpus.length} קבצים אל ${dir.path}');
}

/// כל קבצי הקורפוס: שם → בייטים.
///
/// מופרד מהכתיבה לדיסק כדי שהבדיקות יאמתו את *הפלט של המחולל עצמו* בלי
/// להריץ תת-תהליך — כשהיו שני בוני CFB, פער ביניהם הפך את הקורפוס לחסר
/// ערך בשקט, וזו הבדיקה שמונעת חזרה של זה.
Map<String, Uint8List> buildFixtureCorpus() => {
  // ── OOXML ──
  'basic.docx': _buildDocx(_basicWordBody()),
  'advanced.docx': _buildDocx(_richWordBody(), rich: true),
  'basic.docm': _buildDocx(_basicWordBody(macro: true)),
  'basic.dotx': _buildDocx(_basicWordBody(template: true)),
  'basic.dotm': _buildDocx(_basicWordBody(template: true, macro: true)),
  'advanced.dotx': _buildDocx(_richWordBody(), rich: true),

  // ── ODT ──
  'basic.odt': _buildOdt(_basicOdtBody()),
  'advanced.odt': _buildOdt(_richOdtBody(), rich: true),

  // ── RTF ──
  'basic_utf8.rtf': _utf8Bytes(_basicRtf()),
  'hebrew_cp1255.rtf': _latin1Bytes(_cp1255Rtf()),
  'unicode_escapes.rtf': _latin1Bytes(_unicodeEscapeRtf()),
  'advanced.rtf': _utf8Bytes(_richRtf()),

  // ── HTML ──
  'basic.html': _utf8Bytes(_basicHtml()),
  'advanced.html': _utf8Bytes(_richHtml()),
  'hebrew_cp1255.htm': _cp1255Bytes(_legacyHebrewHtml()),

  // ── Word שנשמר כ-XML ──
  'flat_opc.xml': _buildFlatOpc(_basicWordBody()),
  'wordml_2003.xml': _buildWordMl2003(),

  // ── Word בינארי ──
  'basic.doc': buildWordBinary(_basicDocPieces()),
  'hebrew_legacy.doc': buildWordBinary(_hebrewDocPieces()),
  'advanced.doc': buildWordBinary(_richDocPieces()),
  'basic.dot': buildWordBinary(_basicDocPieces(), template: true),
  'word_binary.wbk': buildWordBinary(_basicDocPieces()),
  'ooxml_like.wbk': _buildDocx(_basicWordBody()),

  // ── מקרי קצה שליליים ──
  'corrupted.docx': _utf8Bytes('PKזבל שאינו ZIP תקין'),
  'corrupted.odt': _utf8Bytes('PKזבל שאינו ZIP תקין'),
  'corrupted.rtf': _rtfBytes('rtf1', 'ansi', ' קבוצה שלא נסגרה'),
  'corrupted.doc': _utf8Bytes('לא CFB בכלל'),
  'encrypted.doc': buildWordBinary(_basicDocPieces(), encrypted: true),
  'fake.docx': _utf8Bytes('זה קובץ טקסט רגיל עם סיומת docx'),
  'fake.odt': _utf8Bytes('זה קובץ טקסט רגיל עם סיומת odt'),
  // .xml שאינו Word — הסורק אמור לדלג עליו לפי תוכנו ולא לאסוף אותו כספר.
  'not_word.xml': _utf8Bytes(
    '<?xml version="1.0"?><config><item>ערך</item></config>',
  ),
  'empty.docx': _buildDocx(''),
  'empty.rtf': _rtfBytes('rtf1', 'ansi', ''),
  'empty.html': _utf8Bytes(
    '<html><head><title>ריק</title></head>'
    '<body></body></html>',
  ),
  'invalid.wbk': _utf8Bytes('%PDF-1.7 גיבוי שאינו Word כלל'),
  // חבילת ZIP שהוסוותה בסיומת .html — אין לקרוא אותה כטקסט.
  'fake.html': _buildDocx(_basicWordBody()),
};

Uint8List _utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));
Uint8List _latin1Bytes(String text) => Uint8List.fromList(latin1.encode(text));

/// קידוד Windows-1255 — ISO-8859-8 חופף לו בטווח האותיות העבריות, וזה כל
/// מה שהדגימה מכילה מעבר ל-ASCII.
Uint8List _cp1255Bytes(String text) => Uint8List.fromList(
  text.runes
      .map((r) => r >= 0x05D0 && r <= 0x05EA ? r - 0x05D0 + 0xE0 : r)
      .toList(),
);

// ═══ HTML ══════════════════════════════════════════════════════════════════

String _basicHtml() =>
    '<!DOCTYPE html><html dir="rtl"><head><meta charset="utf-8">'
    '<title>בדיקה</title></head><body>'
    '<p>שלום עולם — מסמך בדיקה בסיסי של אוצריא</p>'
    '</body></html>';

/// מסמך עשיר: כותרות, עיצוב תווים, רשימות, טבלה, תמונה מוטמעת ועוגן פנימי —
/// **ולצדם** כל מה שהממיר חייב למחוק: סקריפט, מטפל אירועים, `javascript:`,
/// תמונה מהרשת, iframe וטקסט מוסתר.
String _richHtml() =>
    '<!DOCTYPE html><html dir="rtl"><head><meta charset="utf-8">'
    '<script>alert("לא אמור להופיע")</script>'
    '<style>body { color: red }</style></head>'
    '<body onload="track()">'
    '<h1>מסמך בדיקה מתקדם לאוצריא</h1>'
    '<h2>פרק ראשון — בראשית</h2>'
    '<p>פסקת פתיחה רגילה בעברית, לבדיקת כיווניות RTL.</p>'
    '<p><b>טקסט מודגש</b> ואחריו <i>טקסט נטוי</i> ו-<u>קו תחתי</u>, '
    'וכן <font color="#c00000">טקסט צבוע</font>.</p>'
    '<h3>סימן א — רשימות</h3>'
    '<ol type="a"><li>פריט ראשון ברשימה</li>'
    '<li>פריט שני<ul><li>תת-פריט מקונן</li></ul></li></ol>'
    '<h3>סעיף קטן — טבלה</h3>'
    '<table><tr><th>כותרת א</th><th>כותרת ב</th></tr>'
    '<tr><td>ערך 1</td><td>ערך 2</td></tr></table>'
    '<h3>סעיף קטן — הערות שוליים ומבנים</h3>'
    '<p>מילה<sup class="footnote-marker">1</sup>'
    '<i class="footnote">גוף ההערה, שאינו מוצג בגוף הספר.</i> והמשך.</p>'
    '<p><ruby>אנפין<rt>פנים</rt></ruby> עם פירוש מעל.</p>'
    '<blockquote>ציטוט מוזח משני הצדדים.</blockquote>'
    '<details><summary>הצג עוד</summary>תוכן מתקפל.</details>'
    '<hr style="border-top:3px solid #8B0000;">'
    '<div style="border:1px solid #8B0000; padding:10px;">תיבה ממוסגרת</div>'
    '<h2>פרק שני — מדיה וקישורים</h2>'
    '<p><img src="data:image/png;base64,${base64Encode(_tinyPng)}" '
    'width="24" height="24" alt="אייקון"></p>'
    '<p><img src="https://tracker.example/pixel.png"></p>'
    '<p><a href="https://otzaria.org">קישור פתוח</a>, '
    '<a href="book://ברכות#דף ב:">קישור לספר</a>, '
    '<a href="javascript:steal()">קישור חסום</a>, '
    '<a href="otzaria://note?line=3">סכימה שמורה</a>, '
    '<a href="#סיום">קישור פנימי</a>.</p>'
    '<iframe src="https://evil.example">מסגרת</iframe>'
    '<p style="display:none">טקסט מוסתר</p>'
    '<p style="transform:rotate(5deg); position:absolute">עיצוב מתקדם</p>'
    '<p id="סיום">סיום המסמך.</p>'
    '</body></html>';

/// דף עברי ישן: קידוד Windows-1255 מוצהר ב-`http-equiv`, בלי BOM.
String _legacyHebrewHtml() =>
    '<html><head>'
    '<meta http-equiv="Content-Type" content="text/html; '
    'charset=windows-1255"></head><body>'
    '<p>שלום עולם בקידוד ישן</p></body></html>';

// ═══ OOXML ═════════════════════════════════════════════════════════════════

const _wordNs =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/'
    'wordprocessingDrawing"';

String _wordParagraph(String text, {String? style}) {
  final properties = style == null
      ? ''
      : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>';
  return '<w:p>$properties<w:r><w:t xml:space="preserve">$text</w:t></w:r>'
      '</w:p>';
}

String _basicWordBody({bool template = false, bool macro = false}) {
  final kind = template ? 'תבנית' : 'מסמך';
  final suffix = macro ? ' הכולל מאקרו' : '';
  return _wordParagraph('שלום עולם — $kind בדיקה בסיסי$suffix של אוצריא');
}

/// מסמך עשיר: כותרות בשלוש רמות, עיצוב תווים, רשימה ממוספרת, טבלה מקוננת,
/// הערת שוליים ותמונה מוטמעת — חתך שמכסה את רוב יכולות הממיר.
String _richWordBody() {
  return '${_wordParagraph('מסמך בדיקה מתקדם לאוצריא')}'
      '${_wordParagraph('פרק ראשון — בראשית', style: 'Heading1')}'
      '${_wordParagraph('פסקת פתיחה רגילה בעברית, לבדיקת כיווניות RTL.')}'
      '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">טקסט מודגש</w:t>'
      '</w:r><w:r><w:t xml:space="preserve"> ואחריו </w:t></w:r>'
      '<w:r><w:rPr><w:i/></w:rPr><w:t>טקסט נטוי</w:t></w:r>'
      '<w:r><w:t xml:space="preserve"> ו-</w:t></w:r>'
      '<w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>קו תחתי</w:t></w:r>'
      '</w:p>'
      '${_wordParagraph('סימן א — רשימות', style: 'Heading2')}'
      '${_numberedItem(0, 'פריט ראשון ברשימה')}'
      '${_numberedItem(0, 'פריט שני')}'
      '${_numberedItem(1, 'תת-פריט מקונן')}'
      '${_wordParagraph('סעיף קטן — טבלה', style: 'Heading3')}'
      '${_wordTable()}'
      '<w:p><w:r><w:t xml:space="preserve">פסקה עם הערת שוליים</w:t></w:r>'
      '<w:r><w:footnoteReference w:id="2"/></w:r></w:p>'
      '${_wordParagraph('פרק שני — מדיה', style: 'Heading1')}'
      '<w:p><w:r><w:drawing><wp:inline><a:graphic><a:graphicData>'
      '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/'
      'picture"><pic:blipFill><a:blip r:embed="rId1"/></pic:blipFill></pic:pic>'
      '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
      '${_wordParagraph('סיום המסמך.')}';
}

String _numberedItem(int level, String text) =>
    '<w:p><w:pPr><w:numPr><w:ilvl w:val="$level"/><w:numId w:val="1"/>'
    '</w:numPr></w:pPr><w:r><w:t xml:space="preserve">$text</w:t></w:r></w:p>';

String _wordTable() {
  String cell(String text) => '<w:tc>${_wordParagraph(text)}</w:tc>';
  return '<w:tbl>'
      '<w:tr>${cell('כותרת א')}${cell('כותרת ב')}</w:tr>'
      '<w:tr>${cell('ערך 1')}${cell('ערך 2')}</w:tr>'
      '<w:tr>${cell('ערך 3')}${cell('ערך 4')}</w:tr>'
      '</w:tbl>';
}

const _wordStyles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
    '2006/main">'
    '<w:style w:type="paragraph" w:styleId="Heading1">'
    '<w:name w:val="heading 1"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2">'
    '<w:name w:val="heading 2"/><w:pPr><w:outlineLvl w:val="1"/></w:pPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3">'
    '<w:name w:val="heading 3"/><w:pPr><w:outlineLvl w:val="2"/></w:pPr>'
    '</w:style>'
    '</w:styles>';

const _wordNumbering =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
    '2006/main">'
    '<w:abstractNum w:abstractNumId="0">'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="hebrew1"/>'
    '<w:lvlText w:val="%1."/></w:lvl>'
    '<w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
    '<w:lvlText w:val="%1.%2."/></w:lvl>'
    '</w:abstractNum>'
    '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
    '</w:numbering>';

const _wordFootnotes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/'
    '2006/main">'
    '<w:footnote w:id="2"><w:p><w:r>'
    '<w:t>גוף הערת השוליים — נבדק שהוא מופיע inline.</w:t>'
    '</w:r></w:p></w:footnote>'
    '</w:footnotes>';

Uint8List _buildDocx(String body, {bool rich = false}) {
  final document =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document $_wordNs><w:body>$body</w:body></w:document>';

  return buildOoxmlPackage(
    document: document,
    styles: rich ? _wordStyles : null,
    numbering: rich ? _wordNumbering : null,
    footnotes: rich ? _wordFootnotes : null,
    rels: rich ? _richImageRels : null,
    media: rich ? {'image1.png': _tinyPng} : const {},
  );
}

/// עוטף גוף מסמך כחבילת Flat OPC — חבילת OOXML שנשטחה לקובץ .xml אחד.
Uint8List _buildFlatOpc(String body) {
  final document = '<w:document $_wordNs><w:body>$body</w:body></w:document>';
  return _utf8Bytes(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<?mso-application progid="Word.Document"?>'
    '<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/'
    'xmlPackage">'
    '<pkg:part pkg:name="/word/document.xml" '
    'pkg:contentType="application/xml">'
    '<pkg:xmlData>$document</pkg:xmlData></pkg:part>'
    '</pkg:package>',
  );
}

/// מסמך WordprocessingML 2003 — הדיאלקט השני של .xml, עם שורש
/// `w:wordDocument` וגוף עטוף ב-`wx:sect`.
Uint8List _buildWordMl2003() => _utf8Bytes(
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
  '<?mso-application progid="Word.Document"?>'
  '<w:wordDocument '
  'xmlns:w="http://schemas.microsoft.com/office/word/2003/wordml" '
  'xmlns:wx="http://schemas.microsoft.com/office/word/2003/auxHint">'
  '<w:styles><w:style w:type="paragraph" w:styleId="1">'
  '<w:name w:val="heading 1"/></w:style></w:styles>'
  '<w:body><wx:sect>'
  '<w:p><w:pPr><w:pStyle w:val="1"/></w:pPr>'
  '<w:r><w:t>כותרת</w:t></w:r></w:p>'
  '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>פסקה מודגשת</w:t></w:r>'
  '<w:r><w:footnote><w:p><w:r><w:t>הערת שוליים</w:t></w:r></w:p>'
  '</w:footnote></w:r></w:p>'
  '</wx:sect></w:body></w:wordDocument>',
);

/// rels שמפנה את `rId1` לתמונה שבמסמך העשיר.
const _richImageRels =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships"><Relationship Id="rId1" Target="media/image1.png" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships/image"/></Relationships>';

// ═══ ODT ═══════════════════════════════════════════════════════════════════

const _odtNs =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
    'xmlns:xlink="http://www.w3.org/1999/xlink"';

String _basicOdtBody() =>
    '<text:p>שלום עולם — מסמך בדיקה בסיסי ODT של אוצריא</text:p>';

String _richOdtBody() {
  String cell(String text) =>
      '<table:table-cell><text:p>$text</text:p></table:table-cell>';
  String item(String text) =>
      '<text:list-item><text:p>$text</text:p></text:list-item>';

  return '<text:p>מסמך בדיקה מתקדם ODT לאוצריא</text:p>'
      '<text:h text:outline-level="1">פרק ראשון — בראשית</text:h>'
      '<text:p>פסקת פתיחה רגילה בעברית, לבדיקת כיווניות RTL.</text:p>'
      '<text:p><text:span text:style-name="Bold">טקסט מודגש</text:span>'
      ' ואחריו <text:span text:style-name="Italic">טקסט נטוי</text:span>'
      ' ו-<text:span text:style-name="Underline">קו תחתי</text:span></text:p>'
      '<text:h text:outline-level="2">סימן א — רשימות</text:h>'
      '<text:list text:style-name="L1">'
      '${item('פריט ראשון ברשימה')}${item('פריט שני')}'
      '<text:list-item><text:list>${item('תת-פריט מקונן')}</text:list>'
      '</text:list-item>'
      '</text:list>'
      '<text:h text:outline-level="3">סעיף קטן — טבלה</text:h>'
      '<table:table>'
      '<table:table-row>${cell('כותרת א')}${cell('כותרת ב')}</table:table-row>'
      '<table:table-row>${cell('ערך 1')}${cell('ערך 2')}</table:table-row>'
      '</table:table>'
      '<text:p>פסקה עם הערת שוליים'
      '<text:note text:note-class="footnote">'
      '<text:note-citation>1</text:note-citation>'
      '<text:note-body><text:p>גוף הערת השוליים ב-ODT.</text:p>'
      '</text:note-body></text:note></text:p>'
      '<text:h text:outline-level="1">פרק שני — מדיה</text:h>'
      '<text:p><draw:frame><draw:image xlink:href="Pictures/image1.png"/>'
      '</draw:frame></text:p>'
      '<text:p><text:a xlink:href="https://otzaria.org">קישור לאוצריא</text:a>'
      '</text:p>'
      '<text:p>סיום המסמך.</text:p>';
}

const _odtAutomaticStyles =
    '<style:style style:name="Bold" style:family="text">'
    '<style:text-properties fo:font-weight="bold"/></style:style>'
    '<style:style style:name="Italic" style:family="text">'
    '<style:text-properties fo:font-style="italic"/></style:style>'
    '<style:style style:name="Underline" style:family="text">'
    '<style:text-properties style:text-underline-style="solid"/></style:style>'
    '<text:list-style style:name="L1">'
    '<text:list-level-style-number text:level="1" style:num-format="א" '
    'style:num-suffix="."/>'
    '<text:list-level-style-number text:level="2" style:num-format="1" '
    'style:num-suffix="." text:display-levels="2"/>'
    '</text:list-style>';

Uint8List _buildOdt(String body, {bool rich = false}) {
  final content =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-content $_odtNs>'
      '<office:automatic-styles>${rich ? _odtAutomaticStyles : ''}'
      '</office:automatic-styles>'
      '<office:body><office:text>$body</office:text></office:body>'
      '</office:document-content>';

  final entries = <String, Uint8List>{
    'mimetype': _utf8Bytes('application/vnd.oasis.opendocument.text'),
    'META-INF/manifest.xml': _utf8Bytes(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:'
      'xmlns:manifest:1.0"><manifest:file-entry manifest:full-path="/" '
      'manifest:media-type="application/vnd.oasis.opendocument.text"/>'
      '</manifest:manifest>',
    ),
    'content.xml': _utf8Bytes(content),
    'styles.xml': _utf8Bytes(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-styles $_odtNs><office:styles>'
      '<style:style style:name="Heading_20_1" style:family="paragraph" '
      'style:default-outline-level="1"/>'
      '</office:styles></office:document-styles>',
    ),
  };
  if (rich) entries['Pictures/image1.png'] = _tinyPng;
  return _zip(entries);
}

// ═══ RTF ═══════════════════════════════════════════════════════════════════

String _basicRtf() =>
    r'{\rtf1\ansi\ansicpg1255 שלום עולם — מסמך בדיקה בסיסי RTF\par}';

/// עברית מקודדת ב-`\'hh` כפי ש-Word שומר; הקובץ אינו UTF-8 תקין.
String _cp1255Rtf() {
  String escape(String hebrew) {
    const map = {
      'א': 'e0',
      'ב': 'e1',
      'ג': 'e2',
      'ד': 'e3',
      'ה': 'e4',
      'ו': 'e5',
      'ז': 'e6',
      'ח': 'e7',
      'ט': 'e8',
      'י': 'e9',
      'ך': 'ea',
      'כ': 'eb',
      'ל': 'ec',
      'ם': 'ed',
      'מ': 'ee',
      'ן': 'ef',
      'נ': 'f0',
      'ס': 'f1',
      'ע': 'f2',
      'ף': 'f3',
      'פ': 'f4',
      'ץ': 'f5',
      'צ': 'f6',
      'ק': 'f7',
      'ר': 'f8',
      'ש': 'f9',
      'ת': 'fa',
    };
    final buffer = StringBuffer();
    for (final ch in hebrew.split('')) {
      final hex = map[ch];
      buffer.write(hex == null ? ch : "\\'$hex");
    }
    return buffer.toString();
  }

  return '{\\rtf1\\ansi\\ansicpg1255 '
      '${escape('שלום עולם')} - RTF Windows-1255\\par'
      '\\b ${escape('מודגש')}\\b0  ${escape('רגיל')}\\par}';
}

String _unicodeEscapeRtf() {
  // `\uc1` מחייב תו-גיבוי אחרי כל `\uN`; בלעדיו הקורא בולע את התו הבא —
  // וזה בדיוק מה ש-Word כותב (`?` כגיבוי).
  String escape(String text) => text
      .split('')
      .map((c) => c.codeUnitAt(0) < 128 ? c : '\\u${c.codeUnitAt(0)} ?')
      .join();
  return '{\\rtf1\\ansi\\uc1 ${escape('שלום עולם')} - RTF Unicode Escapes'
      '\\par}';
}

/// RTF עשיר: stylesheet עם כותרות, עיצוב תווים, רשימה, טבלה והערת שוליים.
String _richRtf() {
  return r'{\rtf1\ansi\ansicpg1255\uc1'
      r'{\fonttbl{\f0\fnil David;}}'
      r'{\stylesheet{\s1 heading 1;}{\s2 heading 2;}{\s3 heading 3;}}'
      r'{\info{\author מחולל הבדיקות}{\title כותרת פנימית שאין להציג}}'
      ' מסמך בדיקה מתקדם RTF לאוצריא\\par'
      r'\s1\outlinelevel0 פרק ראשון — בראשית\par'
      r'\pard פסקת פתיחה רגילה בעברית, לבדיקת כיווניות RTL.\par'
      r'\b טקסט מודגש\b0  ואחריו \i טקסט נטוי\i0  ו-\ul קו תחתי\ulnone \par'
      r'\s2\outlinelevel1 סימן א — רשימות\par'
      r'\pard{\*\listtext א.\tab}פריט ראשון ברשימה\par'
      r'{\*\listtext ב.\tab}פריט שני\par'
      r'\s3\outlinelevel2 סעיף קטן — טבלה\par'
      r'\pard\trowd כותרת א\cell כותרת ב\cell\row'
      r'\trowd ערך 1\cell ערך 2\cell\row'
      r'\pard פסקה עם הערת שוליים{\footnote גוף הערת השוליים ב-RTF.}\par'
      r'\qc פסקה ממורכזת\par'
      r'\pard שורה ראשונה\line שורה שנייה באותה פסקה\par'
      r'סיום המסמך.\par}';
}

// ═══ Word בינארי ═══════════════════════════════════════════════════════════
//
// הבנייה עצמה ב-`src/document_fixtures/word_binary_builder.dart`, המשותף
// למחולל ולבדיקות. כאן רק *תוכן* המסמכים.

String _p(String text) => '$text\r';

List<WordPiece> _basicDocPieces() => [
  WordPiece(_p('שלום עולם — מסמך בדיקה בסיסי DOC בינארי')),
];

List<WordPiece> _hebrewDocPieces() => [
  const WordPiece('Otzaria ', compressed: true),
  WordPiece(_p('— בדיקת עברית ב-DOC ישן')),
  WordPiece(_p('שורה שנייה בעברית מלאה')),
  const WordPiece('Mixed English piece ', compressed: true),
  WordPiece(_p('וחזרה לעברית באותה פסקה')),
];

/// מסמך בינארי עשיר ככל שהמנוע תומך: המנוע מחלץ טקסט, ולכן העושר כאן הוא
/// במבנה — פסקאות מרובות, קידוד מעורב, תווי בקרה ושדה.
List<WordPiece> _richDocPieces() {
  final fieldBegin = String.fromCharCode(0x13);
  final fieldSeparator = String.fromCharCode(0x14);
  final fieldEnd = String.fromCharCode(0x15);
  final lineBreak = String.fromCharCode(0x0B);
  final cellEnd = String.fromCharCode(0x07);

  return [
    WordPiece(_p('מסמך בדיקה מתקדם DOC בינארי')),
    WordPiece(_p('פרק ראשון — בראשית')),
    WordPiece(_p('פסקת פתיחה רגילה בעברית, לבדיקת כיווניות RTL.')),
    WordPiece(
      'שורה ראשונה$lineBreak'
      'שורה שנייה באותה פסקה\r',
    ),
    const WordPiece(
      'English paragraph in a compressed piece.\r',
      compressed: true,
    ),
    WordPiece(
      'לפני$fieldBegin HYPERLINK "https://otzaria.org" '
      '$fieldSeparator קישור$fieldEnd אחרי\r',
    ),
    WordPiece(
      'תא א$cellEnd'
      'תא ב$cellEnd',
    ),
    WordPiece(_p('סיום המסמך.')),
  ];
}

// ═══ מכולת ZIP ═════════════════════════════════════════════════════════════

/// ארכיון ZIP מרשומות בזיכרון. משתמש ב-`archive` — אותה ספרייה שהממירים
/// קוראים איתה, כך שאין פער בין מה שנכתב למה שנקרא.
Uint8List _zip(Map<String, Uint8List> entries) {
  final archive = Archive();
  entries.forEach(
    (name, data) => archive.addFile(ArchiveFile(name, data.length, data)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// בונה מסמך RTF מ-שתי פקודות פתיחה וגוף. הפרדה זו נחוצה כי מחרוזות עם
/// לוכסנים אחורניים נשברות בקלות בעריכות אוטומטיות.
Uint8List _rtfBytes(String first, String second, String body) {
  const slash = r'\';
  return _utf8Bytes('{$slash$first$slash$second$body}');
}
