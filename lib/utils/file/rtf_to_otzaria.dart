import 'dart:convert';
import 'dart:typed_data';

import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/text/html_escape.dart';
import 'package:otzaria/utils/text/inline_style.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';

/// גרסת ממיר ה-RTF. **חובה להעלות בכל שינוי שמשפיע על הפלט** — הגרסה חלק
/// ממפתח-התוקף של המטמון.
const int kRtfConverterVersion = 8;

/// רווח קשיח. `\tab` ו-`\~` מייצגים רווחים שהמסמך דורש שיישמרו, ורווח
/// רגיל היה נבלע ברינדור ה-HTML.
const String _nbsp = ' ';

/// תווים שפקודת RTF מייצגת. בלעדיהם הפקודה נופלת ל"פקודה לא מוכרת"
/// והתו **נמחק בשקט** — קו מפריד שנעלם מכל משפט במסמך.
const Map<String, String> _characterControlWords = {
  'emdash': '—',
  'endash': '–',
  'bullet': '•',
  'lquote': '‘',
  'rquote': '’',
  'ldblquote': '“',
  'rdblquote': '”',
  'emspace': ' ',
  'enspace': ' ',
  'qmspace': ' ',
  'zwj': '\u200d',
  'zwnj': '\u200c',
  'ltrmark': '\u200e',
  'rtlmark': '\u200f',
};

/// ממיר מסמך RTF לטקסט של אוצריא.
///
/// RTF אינו XML אלא זרם של קבוצות ופקודות עם *מצב* מצטבר (עיצוב, דף-קוד,
/// יעד נוכחי). לכן זהו parser מלא ולא הסרת פקודות ב-regex: הסרה נאיבית
/// מוחקת תוכן אמיתי (טבלת הגופנים בולעת טקסט), משאירה פקודות שנראות כטקסט,
/// ומשמידה עברית שמקודדת ב-`\'hh`.
///
/// [embedImages] כבוי משאיר תג `<img>` ריק, כדי שמבנה השורות יישמר.
String rtfToText(Uint8List bytes, String title, {bool embedImages = true}) {
  // תחביר ה-RTF כולו ASCII, ולכן שני הפענוחים משמרים אותו. UTF-8 קודם: יש
  // כלים ששומרים עברית כבייטים גולמיים במקום ב-`\'hh`, ופענוח latin1 היה
  // הופך אותה לג'יבריש. קובץ עם `\'hh` נכשל ב-UTF-8 ונופל ל-latin1, שם
  // הבייטים הגבוהים נשמרים לטיפול לפי דף-הקוד שהוצהר.
  String source;
  var rawBytes = false;
  try {
    source = utf8.decode(bytes);
  } on FormatException {
    source = latin1.decode(bytes, allowInvalid: true);
    rawBytes = true;
  }
  if (!source.trimLeft().startsWith(r'{\rtf')) {
    throw CorruptedDocumentException(
      format: DocumentFormat.rtf,
      cause: r'הקובץ אינו פותח ב-{\rtf',
    );
  }
  return _RtfParser(
    source,
    title,
    embedImages: embedImages,
    rawBytes: rawBytes,
  ).run();
}

/// יעד הכתיבה הנוכחי. קבוצות שאינן תוכן (טבלת גופנים, מידע) נבלעות
/// במלואן — הטקסט שבתוכן אינו חלק מהמסמך.
enum _Destination {
  body,
  skip,
  footnote,
  listText,
  styleSheet,
  picture,
  fontTable,
  colorTable,
  textBox,

  /// שם וערך של מאפיין שייף (`{\sp{\sn fLine}{\sv 0}}`) — משם נלקח, למשל,
  /// האם לתיבת-הטקסט יש גבול מצויר.
  shapePropertyName,
  shapePropertyValue,
}

/// `\fcharsetN` → דף-קוד של Windows. רק ה-charsets שיש להם פענוח בפועל
/// (ראו `decodeCodepageByte`) — השאר נשארים על דף-הקוד המוצהר.
const Map<int, int> _charsetCodepages = {
  0: 1252, // ANSI
  177: 1255, // עברית
  238: 1252, // מרכז אירופה — הקירוב הטוב ביותר הקיים
};

int? _codepageForCharset(int charset) => _charsetCodepages[charset];

/// מצב העיצוב. RTF יורש מצב אל תוך קבוצות מקוננות, ולכן הוא נשמר במחסנית
/// ומשוחזר ביציאה מכל `}`.
class _RtfState {
  int groupTextStart;
  bool bold;
  bool italic;
  bool underline;
  UnderlineKind underlineKind;
  bool underlineThick;
  int? underlineColorIndex;
  bool strike;
  bool doubleStrike;

  /// טקסט מוסתר (`\v`) — קיים במסמך ואינו אמור להיראות.
  bool hidden;
  int? colorIndex;
  int? highlightIndex;
  String? verticalAlign;
  int codepage;
  int unicodeSkip;
  int? outlineLevel;
  int? styleIndex;
  int? fontIndex;
  String? textAlign;

  /// כיוון הפסקה (`\rtlpar`/`\ltrpar`). קובע את משמעות `\ql`/`\qr`.
  bool rtlPar;
  _Destination destination;

  _RtfState({
    this.groupTextStart = 0,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.underlineKind = UnderlineKind.single,
    this.underlineThick = false,
    this.underlineColorIndex,
    this.strike = false,
    this.doubleStrike = false,
    this.hidden = false,
    this.colorIndex,
    this.highlightIndex,
    this.verticalAlign,
    this.codepage = 1252,
    this.unicodeSkip = 1,
    this.outlineLevel,
    this.styleIndex,
    this.fontIndex,
    this.textAlign,
    this.rtlPar = false,
    this.destination = _Destination.body,
  });

  _RtfState clone() => _RtfState(
    groupTextStart: groupTextStart,
    bold: bold,
    italic: italic,
    underline: underline,
    underlineKind: underlineKind,
    underlineThick: underlineThick,
    underlineColorIndex: underlineColorIndex,
    strike: strike,
    doubleStrike: doubleStrike,
    hidden: hidden,
    colorIndex: colorIndex,
    highlightIndex: highlightIndex,
    verticalAlign: verticalAlign,
    codepage: codepage,
    unicodeSkip: unicodeSkip,
    outlineLevel: outlineLevel,
    styleIndex: styleIndex,
    fontIndex: fontIndex,
    textAlign: textAlign,
    rtlPar: rtlPar,
    destination: destination,
  );

  /// `\plain` מאפס עיצוב תווים בלבד — לא את היעד ולא את דף-הקוד.
  void resetCharacterFormatting() {
    bold = false;
    italic = false;
    underline = false;
    underlineKind = UnderlineKind.single;
    underlineThick = false;
    underlineColorIndex = null;
    strike = false;
    doubleStrike = false;
    hidden = false;
    colorIndex = null;
    highlightIndex = null;
    verticalAlign = null;
  }

  /// `\pard` מאפס מאפייני פסקה בלבד.
  void resetParagraphFormatting() {
    outlineLevel = null;
    styleIndex = null;
    textAlign = null;
    rtlPar = false;
  }
}

class _RtfParser {
  _RtfParser(
    this._source,
    this._title, {
    required this.embedImages,
    required this.rawBytes,
  });

  final String _source;
  final String _title;
  final bool embedImages;

  /// המקור נקרא כ-latin1, ולכן כל תו בו הוא **בית גולמי** ולא נקודת קוד.
  /// בית גבוה חייב לעבור דרך דף-הקוד שהמסמך הצהיר עליו.
  final bool rawBytes;

  final List<String> _output = [];
  final List<_RtfState> _stack = [];
  _RtfState _state = _RtfState();

  /// הפסקה הנבנית כרגע. RTF מסיים פסקה ב-`\par`, ולכן היא נצברת עד אז.
  final StringBuffer _paragraph = StringBuffer();

  /// תווית פריט הרשימה (`\listtext`/`\pntext`) שנצברת לפני תוכן הפסקה.
  final StringBuffer _listLabel = StringBuffer();

  /// מספר תווי-הגיבוי שיש לדלג עליהם אחרי `\uN`.
  int _pendingUnicodeSkip = 0;

  /// ה-run הנצבר: טקסט ותגי העיצוב שתחתיהם נכתב.
  final StringBuffer _pendingText = StringBuffer();
  int _textPosition = 0;
  String _pendingOpen = '';
  String _pendingClose = '';
  _Destination _pendingDestination = _Destination.body;

  /// אינדקס סגנון → שם, מתוך `\stylesheet`. משמש לזיהוי כותרות.
  final Map<int, String> _styleNames = {};
  final StringBuffer _styleName = StringBuffer();
  int? _styleBeingDefined;

  /// אינדקס גופן → דף-קוד, מתוך `\fonttbl`. [_pendingFontCharset] מכסה את
  /// הסדר ההפוך (`\fcharset` לפני `\f`), שקיים בכלים שאינם Word.
  final Map<int, int> _fontCodepages = {};
  int? _fontBeingDefined;
  int? _pendingFontCharset;

  /// טבלת הצבעים (`\colortbl`). האינדקס הוא סדר ההגדרה, ו-`\cf0` הוא
  /// "אוטומטי" — ערך `null` שאין לצייר.
  final List<String?> _colorTable = [];
  int? _pendingRed;
  int? _pendingGreen;
  int? _pendingBlue;

  /// טבלה נבנית: תאי השורה הנוכחית ושורות הטבלה שטרם נסגרה.
  final List<_RtfCell> _rowCells = [];
  final List<_RtfRow> _tableRows = [];
  bool _inTable = false;

  /// הגדרות התאים של השורה הנוכחית, לפי סדר ה-`\cellx`. ב-RTF מאפייני התא
  /// נכתבים **לפני** תוכנו, ולכן הם נצברים ומותאמים בסוף השורה.
  final List<_RtfCellDef> _cellDefs = [];
  _RtfCellDef _cellDef = _RtfCellDef();
  bool _rowIsHeader = false;
  bool _rowIsRtl = false;

  /// תוכן תיבת-הטקסט הנצברת (`\shptxt`).
  final StringBuffer _textBox = StringBuffer();

  /// מאפייני השייף הנוכחי (`\sn` → `\sv`). נצברים רק למאפיינים שמעניינים
  /// אותנו — ערך `pib` הוא התמונה עצמה, מגה-בייטים שאין טעם לצבור.
  final Map<String, String> _shapeProperties = {};
  final StringBuffer _shapeProperty = StringBuffer();
  String? _pendingShapeProperty;

  /// המאפיינים היחידים שנקראים מתוך `\*\shpinst`.
  static const Set<String> _wantedShapeProperties = {'fLine'};

  int _footnoteNumber = 1;
  final StringBuffer _footnote = StringBuffer();

  /// סימן הערה מילולי (בלי `\chftn`) והמשכו אחרי הקבוצה (`4{\footnote…}0`).
  String _footnoteMark = '';
  ({String open, String close}) _footnoteMarkTags = (open: '', close: '');
  int _footnoteMarkDepth = 0;
  String _footnoteMarkRest = '';

  /// הבייטים ההקסדצימליים של תמונה שנצברת (`\pict`). האורך נמנה בנפרד, כי
  /// בלי הטמעה הבייטים עצמם אינם נצברים.
  final StringBuffer _pictureHex = StringBuffer();
  int _pictureHexLength = 0;
  String? _pictureMime;

  /// האם ה-`\pict` הנוכחי הוא תמונה מוכרת. נפרד מ-[_pictureMime]: פורמט
  /// וקטורי (WMF/EMF) הוא תמונה שאין לה data URI לרינדור.
  bool _isPicture = false;

  String run() {
    _output.add(otzariaInlineText('<h1>${escapeHtmlText(_title)}</h1>'));
    _parse();
    // קבוצה שלא נסגרה (קובץ קטוע): מה שנצבר בה היה נמחק בשקט.
    _flushRun();
    if (_footnote.isNotEmpty || _footnoteMark.isNotEmpty) _emitFootnote();
    // שורה שה-`\row` שלה חסר (קובץ קטוע, או `\cell` בלי `\trowd`) — התאים
    // שנצברו בה היו נעלמים בשקט.
    if (_paragraph.isNotEmpty || _pendingText.isNotEmpty) {
      if (_rowCells.isNotEmpty) _endCell();
    }
    if (_rowCells.any((cell) => cell.html.isNotEmpty)) _endRow();
    _rowCells.clear();
    _flushParagraph();
    _flushTable();
    return _output.join('\n');
  }

  void _parse() {
    var i = 0;
    while (i < _source.length) {
      final char = _source[i];
      switch (char) {
        case '{':
          _stack.add(_state.clone());
          _state.groupTextStart = _textPosition;
          i++;
        case '}':
          _closeGroup();
          i++;
        case '\\':
          i = _readControl(i);
        case '\r':
        case '\n':
          i++; // מעברי שורה בקובץ אינם תוכן; רק `\par` מסיים פסקה.
        default:
          _writeStreamChar(char);
          i++;
      }
    }
  }

  /// תו שנקרא ישירות מזרם המקור.
  ///
  /// יש כלים ששומרים עברית כבייטים גולמיים בדף-הקוד המוצהר במקום ב-`\'hh`.
  /// בקובץ כזה הפענוח נופל ל-latin1, וכל בית עברי היה נשאר אות לטינית —
  /// ספר שלם של ג'יבריש שנראה תקין מבחינה מבנית ולכן אינו נכשל בקול.
  void _writeStreamChar(String char) {
    final unit = char.codeUnitAt(0);
    if (!rawBytes || unit < 0x80) {
      _writeText(char);
      return;
    }
    _writeText(
      String.fromCharCode(decodeCodepageByte(unit, _effectiveCodepage)),
    );
  }

  void _closeGroup() {
    if (_stack.length <= _footnoteMarkDepth) _footnoteMarkRest = '';
    final destination = _state.destination;
    final enclosing = _stack.isEmpty
        ? _Destination.body
        : _stack.last.destination;
    // יעד נגמר רק כשהקבוצה שפתחה אותו נסגרת. קבוצה מקוננת בתוכו (Word עוטף
    // כל מילה בקבוצה) מחזירה את אותו יעד — פליטה שם הייתה מייצרת תיבת-טקסט,
    // הערה או תמונה **נפרדת לכל מילה**.
    if (destination == enclosing) {
      if (_stack.isNotEmpty) _state = _stack.removeLast();
      return;
    }

    _flushRun();
    switch (destination) {
      case _Destination.footnote:
        _emitFootnote();
      case _Destination.picture:
        _emitPicture(enclosing);
      case _Destination.textBox:
        _emitTextBox();
      case _Destination.shapePropertyName:
        _pendingShapeProperty = _shapeProperty.toString().trim();
        _shapeProperty.clear();
      case _Destination.shapePropertyValue:
        final name = _pendingShapeProperty;
        if (name != null) _shapeProperties[name] = _shapeProperty.toString();
        _shapeProperty.clear();
        _pendingShapeProperty = null;
      case _Destination.styleSheet:
        if (_styleBeingDefined != null) {
          _styleNames[_styleBeingDefined!] = _styleName.toString().trim();
          _styleName.clear();
          _styleBeingDefined = null;
        }
      case _Destination.fontTable:
        _fontBeingDefined = null;
        _pendingFontCharset = null;
      case _Destination.body:
      case _Destination.skip:
      case _Destination.listText:
      case _Destination.colorTable:
        break;
    }
    if (_stack.isNotEmpty) _state = _stack.removeLast();
  }

  /// קורא פקודה אחת ומחזיר את המיקום שאחריה.
  int _readControl(int start) {
    var i = start + 1;
    if (i >= _source.length) return i;

    final first = _source[i];

    // `\'hh` — בית בדף-הקוד הנוכחי. חובה לאמת שני ספרות hex: `int.tryParse`
    // מקבל גם סימן, ו-`\'-f` היה מייצר בית שלילי ומקריס את הפענוח.
    if (first == "'") {
      final value =
          i + 3 <= _source.length &&
              _isHexDigit(_source[i + 1]) &&
              _isHexDigit(_source[i + 2])
          ? int.parse(_source.substring(i + 1, i + 3), radix: 16)
          : null;
      if (value != null) {
        if (_pendingUnicodeSkip > 0) {
          _pendingUnicodeSkip--; // תו גיבוי ל-`\u` שכבר נכתב
        } else {
          _writeCodeUnit(decodeCodepageByte(value, _effectiveCodepage));
        }
      }
      // הצמד נצרך גם כשאינו hex תקין — אחרת הוא זולג לגוף הספר כטקסט.
      return i + 3 <= _source.length ? i + 3 : _source.length;
    }

    // תווים נמלטים ותווים מיוחדים.
    if (!_isAlpha(first)) {
      switch (first) {
        case '\\':
        case '{':
        case '}':
          _writeText(first);
        case '~':
          _append(_nbsp); // רווח קשיח — טקסט, ולכן אינו קוטע את ה-run
        case '_':
          _writeText('‑'); // מקף בלתי-שביר
        case '-':
          break; // מקף אופציונלי — נראה רק כשהשורה נשברת בו
        case '*':
          // `\*` מסמן יעד שאפשר להתעלם ממנו אם אינו מוכר.
          return _readIgnorableDestination(i + 1);
        case '\r':
        case '\n':
          _endParagraph();
      }
      return i + 1;
    }

    // מילת-פקודה: אותיות, ואז פרמטר מספרי אופציונלי.
    final wordStart = i;
    while (i < _source.length && _isAlpha(_source[i])) {
      i++;
    }
    final word = _source.substring(wordStart, i);

    int? parameter;
    if (i < _source.length && (_source[i] == '-' || _isDigit(_source[i]))) {
      final numberStart = i;
      if (_source[i] == '-') i++;
      while (i < _source.length && _isDigit(_source[i])) {
        i++;
      }
      parameter = int.tryParse(_source.substring(numberStart, i));
    }
    // רווח יחיד אחרי פקודה הוא מפריד ואינו תוכן.
    if (i < _source.length && _source[i] == ' ') i++;

    // `\binN` — N בייטים גולמיים אחריו. בלי הדילוג הם מפורשים כתחביר RTF,
    // וסוגר מקרי בתוכם פורק את מחסנית הקבוצות ומדליף יעדים.
    if (word == 'bin' && parameter != null && parameter > 0) {
      return i + parameter > _source.length ? _source.length : i + parameter;
    }

    _applyControlWord(word, parameter);
    return i;
  }

  /// `\*\destination` — קבוצה שאפשר להתעלם ממנה. יעדים שאנו יודעים לקרוא
  /// ממשיכים כרגיל; כל השאר נבלעים, וכך אין דליפת מטא-דאטה לטקסט.
  int _readIgnorableDestination(int start) {
    var i = start;
    if (i < _source.length && _source[i] == '\\') {
      i++;
      final wordStart = i;
      while (i < _source.length && _isAlpha(_source[i])) {
        i++;
      }
      final word = _source.substring(wordStart, i);
      if (i < _source.length && _source[i] == ' ') i++;
      if (word == 'listtext' || word == 'pntext') {
        _state.destination = _Destination.listText;
        return i;
      }
      // `\*\shppict` היא עטיפה שקופה סביב התמונה **הראשית** של Word; בליעתה
      // מוחקת את כל התמונות במסמך. העותק הכפול הוא `\nonshppict`.
      if (word == 'shppict') return i;
      // `\*\shpinst` היא גוף האובייקט הצף. היא נבלעת (המאפיינים שבה אינם
      // תוכן), אך `\shptxt` שבתוכה מחזיר את היעד לגוף התיבה.
      if (word == 'shpinst') {
        _state.destination = _Destination.skip;
        _shapeProperties.clear();
        _pendingShapeProperty = null;
        return i;
      }
    }
    _state.destination = _Destination.skip;
    return i;
  }

  void _applyControlWord(String word, int? parameter) {
    // תו שהפקודה מייצגת — חייב להיבדק לפני ה-switch, אחרת הוא נמחק בשקט.
    final character = _characterControlWords[word];
    if (character != null) {
      _writeText(character);
      return;
    }

    switch (word) {
      // ── יעדים ──
      case 'fonttbl':
        _state.destination = _Destination.fontTable;
      case 'colortbl':
        _state.destination = _Destination.colorTable;
        _colorTable.clear();
        _resetPendingColor();
      case 'info':
      case 'listtable':
      case 'listoverridetable':
      case 'rsidtbl':
      case 'generator':
      case 'themedata':
      case 'colorschememapping':
      case 'latentstyles':
      case 'datastore':
      case 'xmlnstbl':
      // הוראת שדה (`NOTEREF _Ref…`) — מטא-דאטה ולא תוכן. התוצאה
      // יושבת ב-`fldrslt` ונשמרת (issue #1240 במסלול ה-DOC).
      case 'fldinst':
      // העותק הכפול של תמונה ב-Word; ה-`\*\shppict` שלפניו הוא המקור.
      case 'nonshppict':
        _state.destination = _Destination.skip;
      case 'stylesheet':
        _state.destination = _Destination.styleSheet;
      case 'footnote':
        var markGroup = _stack.length - 1;
        while (markGroup > 0 &&
            _stack[markGroup].groupTextStart == _textPosition &&
            _stack[markGroup - 1].verticalAlign == 'super') {
          markGroup--;
        }
        final isMark =
            !_state.hidden &&
            _state.verticalAlign == 'super' &&
            _pendingOpen.endsWith('<sup>') &&
            _pendingDestination == _Destination.body &&
            markGroup >= 0;
        _footnoteMark = '';
        _footnoteMarkRest = '';
        if (isMark) {
          final text = _pendingText.toString();
          final start =
              (_stack[markGroup].groupTextStart - _textPosition + text.length)
                  .clamp(0, text.length);
          _footnoteMark = text.substring(start);
          _footnoteMarkTags = (open: _pendingOpen, close: _pendingClose);
          _footnoteMarkDepth = markGroup;
          _pendingText.clear();
          _pendingText.write(text.substring(0, start));
          _flushRun();
        }
        _state.destination = _Destination.footnote;
        _footnote.clear();
        // גוף ההערה אינו יורש את עיצוב הסימן; הסתרה נשמרת.
        final hidden = _state.hidden;
        _state.resetCharacterFormatting();
        _state.hidden = hidden;
      case 'chftn':
        _flushRun();
      // טקסט של אובייקט צף (תיבת-טקסט). הוא יושב בתוך `\*\shpinst` הנבלעת,
      // ובלי ההחזרה המפורשת הזו כל תוכן התיבות במסמך נעלם.
      case 'shptxt':
        _state.destination = _Destination.textBox;
        _textBox.clear();
      case 'sn':
        _state.destination = _Destination.shapePropertyName;
        _shapeProperty.clear();
      case 'sv':
        // ערך של מאפיין שאינו מעניין (למשל `pib` — התמונה עצמה) נבלע.
        _state.destination =
            _wantedShapeProperties.contains(_pendingShapeProperty)
            ? _Destination.shapePropertyValue
            : _Destination.skip;
        _shapeProperty.clear();
      case 'pict':
        _state.destination = _Destination.picture;
        _pictureHex.clear();
        _pictureMime = null;
        _isPicture = false;
      case 'pngblip':
        _pictureMime = 'image/png';
        _isPicture = true;
      case 'jpegblip':
        _pictureMime = 'image/jpeg';
        _isPicture = true;
      // פורמטים שאין להם data URI שהקורא מרנדר. הם עדיין תמונה, והתג הריק
      // שומר על מבנה השורות — שעליו מתבססים תוכן העניינים וההערות האישיות.
      case 'emfblip':
      case 'wmetafile':
      case 'pmmetafile':
      case 'dibitmap':
      case 'wbitmap':
        _isPicture = true;

      // ── קידוד ──
      case 'ansicpg':
        if (parameter != null) _state.codepage = parameter;
      case 'uc':
        if (parameter != null) _state.unicodeSkip = parameter.clamp(0, 100);
      case 'u':
        if (parameter != null) {
          // הפרמטר הוא יחידת UTF-16 חתומה; שלילי הוא ייצוג של ערך מעל 0x7FFF.
          _writeCodeUnit(parameter < 0 ? parameter + 65536 : parameter);
          _pendingUnicodeSkip = _state.unicodeSkip;
        }
      case 'f':
        // בתוך `\fonttbl` הפקודה *מגדירה* גופן; בגוף היא בוחרת אותו.
        if (_state.destination == _Destination.fontTable) {
          _fontBeingDefined = parameter;
          _applyFontCharset(parameter, _pendingFontCharset);
        } else {
          _state.fontIndex = parameter;
        }
      case 'fcharset':
        // דף-הקוד האפקטיבי של `\'hh` נגזר מה-charset של הגופן הנוכחי, ולא
        // מ-`\ansicpg` בלבד: מסמך עברי נשמר תדיר עם cp1252 ו-fcharset177.
        _pendingFontCharset = parameter;
        _applyFontCharset(_fontBeingDefined, parameter);

      // ── טבלת צבעים ──
      case 'red':
        _pendingRed = parameter;
      case 'green':
        _pendingGreen = parameter;
      case 'blue':
        _pendingBlue = parameter;

      // ── עיצוב תווים ──
      case 'b':
        _state.bold = parameter != 0;
      case 'i':
        _state.italic = parameter != 0;
      case 'strike':
        _state.strike = parameter != 0;
      case 'striked':
        _state.doubleStrike = parameter != 0;
      // `\v` מסמן טקסט מוסתר: הוא קיים במסמך אך אינו אמור להיראות
      // (אינדקסים, הערות עבודה). הצגתו מזהמת את גוף הספר.
      case 'v':
        _state.hidden = parameter != 0;
      case 'cf':
        _state.colorIndex = parameter;
      case 'highlight':
        _state.highlightIndex = parameter;
      case 'ulc':
        _state.underlineColorIndex = parameter;
      case 'ulnone':
        _state.underline = false;
      case 'super':
        _state.verticalAlign = parameter == 0 ? null : 'super';
      case 'sub':
        _state.verticalAlign = parameter == 0 ? null : 'sub';
      case 'nosupersub':
        _state.verticalAlign = null;
      case 'plain':
        _state.resetCharacterFormatting();

      // ── פסקה ──
      case 'pard':
        _state.resetParagraphFormatting();
      case 'par':
        _endParagraph();
      case 'line':
      case 'softline':
        _writeRaw('<br>');
      // רווח קשיח הוא **טקסט** ולא markup: פליטתו כ-raw קטעה את ה-run
      // המעוצב, ולכן ההדגשה נשברה בדיוק בין המילים.
      case 'tab':
        _append(_nbsp * 4);
      case 'outlinelevel':
        _state.outlineLevel = parameter;
      case 's':
        _state.styleIndex = parameter;
        if (_state.destination == _Destination.styleSheet) {
          _styleBeingDefined = parameter;
          _styleName.clear();
        }
      case 'rtlpar':
        _state.rtlPar = true;
      case 'ltrpar':
        _state.rtlPar = false;
      case 'qc':
        _state.textAlign = 'center';
      case 'qr':
        _state.textAlign = 'right';
      case 'ql':
        _state.textAlign = 'left';
      case 'qj':
        _state.textAlign = null;

      // ── טבלאות ──
      case 'cell':
        _endCell();
      case 'row':
      case 'nestrow':
        _endRow();
      case 'trowd':
        _inTable = true;
        _startRowDefinition();
      case 'intbl':
        _inTable = true;
      case 'trhdr':
        _rowIsHeader = true;
      case 'rtlrow':
      case 'taprtl':
        _rowIsRtl = true;
      case 'ltrrow':
        _rowIsRtl = false;
      case 'cellx':
        _cellDefs.add(_cellDef);
        _cellDef = _RtfCellDef();
      case 'clcbpat':
        _cellDef.backgroundIndex = parameter;
      case 'clvertalt':
        _cellDef.verticalAlign = 'top';
      case 'clvertalc':
        _cellDef.verticalAlign = 'middle';
      case 'clvertalb':
        _cellDef.verticalAlign = 'bottom';
      // רק תאי ה*המשך* נדרשים: תא המיזוג הראשון (`\clmgf`/`\clvmgf`) נפלט
      // כרגיל, וה-colspan/rowspan שלו נספר מהם.
      case 'clmrg':
        _cellDef.horizontalMergeContinue = true;
      case 'clvmrg':
        _cellDef.verticalMergeContinue = true;

      default:
        // וריאנטי קו תחתי (`\uld`, `\uldb`, `\ulwave`, `\ulth`…). כולם
        // פותחים ב-`ul`, ולכן טיפול אחד מכסה את כל התקן — פקודה שלא נזהתה
        // בשמה המלא הייתה מוחקת את הקו כליל.
        if (word.startsWith('ul')) _applyUnderline(word, parameter);
    }
    // פקודה לא מוכרת: מתעלמים ממנה ומשמרים את הטקסט סביבה (§52).
  }

  /// מפעיל וריאנט קו תחתי לפי שם הפקודה (`ul`, `uld`, `uldb`, `ulth`…).
  ///
  /// RTF מקצר את שמות הסוגים (`d` = מנוקד, `db` = כפול) ולכן נדרשת מפה
  /// משלו — התאמה לפי תחילית המילה המלאה החזירה "קו יחיד" לכל הווריאנטים.
  void _applyUnderline(String word, int? parameter) {
    if (parameter == 0) {
      _state.underline = false;
      return;
    }
    var suffix = word.substring(2);
    _state.underline = true;
    // תחילית `th` היא עובי, ואחריה נשאר סוג הקו (`thdash` → `dash`).
    _state.underlineThick = suffix.startsWith('th') && suffix != 'thdashdd';
    if (_state.underlineThick) suffix = suffix.substring(2);
    _state.underlineKind = switch (suffix) {
      'db' => UnderlineKind.double,
      'd' => UnderlineKind.dotted,
      'dash' || 'dashd' || 'dashdd' || 'ldash' => UnderlineKind.dashed,
      // `\ululdbwave` הוא גל כפול — הצורה הגלית היא מה שנראה.
      'wave' || 'hwave' || 'uldbwave' => UnderlineKind.wavy,
      _ => UnderlineKind.single, // ul, ulw (מילים), וכל וריאנט לא מוכר
    };
  }

  void _startRowDefinition() {
    _cellDefs.clear();
    _cellDef = _RtfCellDef();
    _rowIsHeader = false;
    _rowIsRtl = false;
  }

  void _resetPendingColor() {
    _pendingRed = null;
    _pendingGreen = null;
    _pendingBlue = null;
  }

  /// רשומת צבע מסתיימת ב-`;`. רשומה ריקה (בלי `\red`) היא "אוטומטי".
  void _endColorEntry() {
    final r = _pendingRed;
    final g = _pendingGreen;
    final b = _pendingBlue;
    _resetPendingColor();
    if (r == null && g == null && b == null) {
      _colorTable.add(null);
      return;
    }
    String hex(int? v) => (v ?? 0)
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(
          2,
          '0',
        );
    _colorTable.add('#${hex(r)}${hex(g)}${hex(b)}');
  }

  String? _colorAt(int? index) {
    // `\cf0`/`\highlight0` הם "אוטומטי". צבע שחור מפורש מדולג אף הוא —
    // הוא ברירת המחדל ושובר את המצב הכהה.
    if (index == null || index <= 0 || index >= _colorTable.length) return null;
    final color = _colorTable[index];
    if (color == null || color == '#000000') return null;
    return color;
  }

  /// מרקר: כאן שחור **כן** נשמר — מרקר שחור הוא בחירה של המחבר.
  String? _highlightAt(int? index) {
    if (index == null || index <= 0 || index >= _colorTable.length) return null;
    return _colorTable[index];
  }

  /// רקע תא בטבלה. לבן מדולג — הוא ברירת המחדל, וכתיבתו במפורש הופכת את התא
  /// לבלתי-קריא במצב כהה. כך גם ב-ODT וב-OOXML.
  String? _cellBackgroundAt(int? index) {
    final color = _highlightAt(index);
    return color == null || color.toLowerCase() == '#ffffff' ? null : color;
  }

  /// תגי הפתיחה והסגירה של העיצוב הנוכחי. נבנים יחד כדי שיישארו מסונכרנים.
  ({String open, String close}) get _formattingTags {
    final open = StringBuffer();
    final close = <String>[];
    void wrap(({String open, String close}) tags) {
      open.write(tags.open);
      close.insert(0, tags.close);
    }

    if (_state.bold) wrap((open: '<b>', close: '</b>'));
    if (_state.italic) wrap((open: '<i>', close: '</i>'));
    if (_state.underline) {
      wrap(
        underlineTags(
          kind: _state.underlineKind,
          color: _colorAt(_state.underlineColorIndex),
          thick: _state.underlineThick,
        ),
      );
    }
    if (_state.strike || _state.doubleStrike) {
      wrap(strikeTags(doubleLine: _state.doubleStrike));
    }
    final highlight = _highlightAt(_state.highlightIndex);
    if (highlight != null) wrap(highlightTags(highlight));
    final color = _colorAt(_state.colorIndex);
    if (color != null) wrap(colorTags(color));
    if (_state.verticalAlign == 'super') wrap((open: '<sup>', close: '</sup>'));
    if (_state.verticalAlign == 'sub') wrap((open: '<sub>', close: '</sub>'));
    return (open: open.toString(), close: close.join());
  }

  // ── כתיבה ─────────────────────────────────────────────────────────────

  void _writeText(String text) {
    if (_pendingUnicodeSkip > 0) {
      _pendingUnicodeSkip--;
      return;
    }
    _append(escapeHtmlText(text));
  }

  /// [codeUnit] מחוץ לטווח החוקי מושמט. `\uN` בקובץ פגום מגיע עם ערכים
  /// שרירותיים, ו-`String.fromCharCode` היה זורק `RangeError` — חריגה שאינה
  /// [DocumentConversionException] ולכן בורחת מכל מטפל בצנרת.
  void _writeCodeUnit(int codeUnit) {
    if (codeUnit < 0 || codeUnit > 0x10FFFF) return;
    _append(escapeHtmlText(String.fromCharCode(codeUnit)));
  }

  /// כתיבה של markup מוכן שאין לעטוף בתגי עיצוב.
  void _writeRaw(String markup) {
    if (_state.hidden) return;
    _flushRun();
    _writeToDestination(markup);
  }

  /// צובר תווים לתוך run בעל עיצוב אחיד.
  ///
  /// RTF פולט תו-אחר-תו, ובלי הצבירה כל אות הייתה מקבלת עותק מלא של תגי
  /// העיצוב (`<b>ח</b><b>ז</b>…`) — ניפוח HTML של פי עשרות ופגיעה בהדגשת
  /// החיפוש, שמחפשת רצף טקסט.
  void _append(String text) {
    if (text.isEmpty) return;
    // טקסט מוסתר אינו נכתב, אך גם אינו מפסיק את ה-run הנצבר.
    if (_state.hidden) return;
    final rest = _footnoteMarkRest;
    if (rest.isNotEmpty && _state.destination == _Destination.body) {
      final inMark =
          _stack.length >= _footnoteMarkDepth &&
          _state.verticalAlign == 'super' &&
          rest.startsWith(text);
      _footnoteMarkRest = inMark ? rest.substring(text.length) : '';
      if (inMark) return;
    }
    if (_state.destination == _Destination.colorTable) {
      // הרשומות בטבלת הצבעים מופרדות ב-`;` — התו היחיד שיש לו משמעות שם.
      for (final char in text.split('')) {
        if (char == ';') _endColorEntry();
      }
      return;
    }
    final tags = _formattingTags;
    if (_pendingText.isNotEmpty &&
        (tags.open != _pendingOpen ||
            _state.destination != _pendingDestination)) {
      _flushRun();
    }
    _pendingOpen = tags.open;
    _pendingClose = tags.close;
    _pendingDestination = _state.destination;
    _pendingText.write(text);
    _textPosition += text.length;
  }

  void _flushRun() {
    if (_pendingText.isEmpty) return;
    final text = _pendingText.toString();
    _pendingText.clear();
    final open = _pendingOpen;
    final close = _pendingClose;
    final destination = _pendingDestination;
    _pendingOpen = '';
    _pendingClose = '';
    _writeToDestination(
      open.isEmpty ? text : '$open$text$close',
      destination: destination,
    );
  }

  void _writeToDestination(String markup, {_Destination? destination}) {
    switch (destination ?? _state.destination) {
      case _Destination.skip:
      case _Destination.fontTable:
      case _Destination.colorTable:
        return;
      case _Destination.styleSheet:
        if (_styleBeingDefined != null) _styleName.write(markup);
      case _Destination.picture:
        // בלי הטמעה אין צורך בבייטים; צבירת מגה-בייטים של hex לזיכרון רק
        // כדי להשליכם היא בזבוז נטו.
        _pictureHexLength += markup.length;
        if (embedImages) _pictureHex.write(markup);
      case _Destination.listText:
        _listLabel.write(markup);
      case _Destination.footnote:
        _footnote.write(markup);
      case _Destination.textBox:
        _textBox.write(markup);
      case _Destination.shapePropertyName:
      case _Destination.shapePropertyValue:
        _shapeProperty.write(markup);
      case _Destination.body:
        _paragraph.write(markup);
    }
  }

  // ── סיום יחידות ────────────────────────────────────────────────────────

  /// `\par` בתוך הערת שוליים, תיבת-טקסט או תא טבלה הוא מפריד שורה ולא סוף
  /// פסקה: פריקת פסקת הגוף שם הייתה מפצלת אותה במקום הלא נכון, והתעלמות
  /// מוחלטת הייתה מדביקה מילים משתי פסקאות למילה אחת.
  ///
  /// בכל יעד אחר הפריקה מתבצעת כרגיל — `\par` בתוך `\listtext`/`\pict` פירושו
  /// שהקבוצה לא נסגרה (קובץ קטוע), ובלי הפריקה שאר המסמך נמחק בשקט.
  void _endParagraph() {
    _footnoteMarkRest = '';
    if (_state.destination == _Destination.footnote ||
        _state.destination == _Destination.textBox ||
        (_state.destination == _Destination.body && _inTable)) {
      _writeRaw('<br>');
      return;
    }
    _flushParagraph();
  }

  void _flushParagraph() {
    _flushRun();
    // שורות טבלה נצברות עד שמגיע תוכן שאינו טבלה — אחרת כל `\row` היה
    // נסגר כטבלה נפרדת במקום שורה בטבלה אחת.
    _flushTable();
    final label = _listLabel.toString().trim();
    _listLabel.clear();
    final body = _paragraph.toString();
    _paragraph.clear();
    if (body.trim().isEmpty && label.isEmpty) return;

    var text = label.isEmpty ? body : '$label $body';

    final level = _headingLevel();
    if (level != null) {
      _output.add('<h$level>${text.trim()}</h$level>');
      return;
    }
    final align = _resolvedAlign();
    if (align != null) {
      text = '<div style="text-align: $align;">$text</div>';
    }
    _output.add(text);
  }

  /// היישור שיש לסמן, או `null` כשאין מה לסמן.
  ///
  /// בפסקת `\rtlpar` נשמר **מרכוז בלבד**: מפיקי RTF חלוקים בשאלה אם
  /// `\ql`/`\qr` שם הם פיזיים או לוגיים, Word כותב אותם כמעט בכל פסקה,
  /// והכרעה שגויה מיישרת ספר עברי שלם לצד ההפוך.
  String? _resolvedAlign() {
    final align = _state.textAlign;
    if (align == null || align == 'center') return align;
    if (_state.rtlPar) return null;
    return align == 'left' ? null : align; // שמאל הוא הטבעי ב-LTR
  }

  /// רמת כותרת מ-`\outlinelevel` או משם הסגנון ב-`\stylesheet`.
  /// `\outlinelevel` מחוץ לטווח 0–8 אינו כותרת (כמו ב-Word).
  int? _headingLevel() {
    final outline = _state.outlineLevel;
    if (outline != null) {
      if (outline < 0 || outline > 8) return null;
      return (outline + 1).clamp(1, 6);
    }
    final name = _styleNames[_state.styleIndex];
    if (name == null) return null;
    final normalized = name.toLowerCase();
    final match = RegExp(
      r'(?:heading|כותרת)\s*(\d+)',
    ).firstMatch(normalized);
    if (match == null) return null;
    return int.tryParse(match.group(1)!)?.clamp(1, 6);
  }

  void _applyFontCharset(int? font, int? charset) {
    if (font == null || charset == null) return;
    final codepage = _codepageForCharset(charset);
    if (codepage != null) _fontCodepages[font] = codepage;
  }

  /// דף-הקוד של הגופן הנוכחי גובר על `\ansicpg`: כך נשמרת עברית במסמך
  /// שהוצהר cp1252 והגופן שלה הוא `\fcharset177`.
  int get _effectiveCodepage =>
      _fontCodepages[_state.fontIndex] ?? _state.codepage;

  /// `\cell`/`\row` בונים טבלה מפסקת **הגוף**. ביעד אחר (הערה, תמונה, קבוצה
  /// נבלעת) הם תועים, וטיפול בהם היה גוזל את פסקת הגוף לתוך תא.
  bool get _inBody => _state.destination == _Destination.body;

  void _endCell() {
    if (!_inBody) return;
    _flushRun();
    final index = _rowCells.length;
    final def = index < _cellDefs.length ? _cellDefs[index] : _RtfCellDef();
    _rowCells.add(_RtfCell(_trimBreaks(_paragraph.toString()), def));
    _paragraph.clear();
    _listLabel.clear();
  }

  void _endRow() {
    if (!_inBody) return;
    // האיפוס לפני היציאה המוקדמת: שורה בלי תאים (טבלה ריקה, קובץ קטוע) הייתה
    // משאירה את `_inTable` דלוק לנצח, וכל `\par` שאחריה הופך ל-`<br>` —
    // כלומר כל שאר הספר מתמזג לשורה אחת.
    _inTable = false;
    if (_rowCells.isEmpty) return;
    _tableRows.add(
      _RtfRow(
        List<_RtfCell>.of(_rowCells),
        isHeader: _rowIsHeader,
        isRtl: _rowIsRtl,
      ),
    );
    _rowCells.clear();
  }

  void _flushTable() {
    if (_tableRows.isEmpty) return;
    _output.add(_buildTableHtml(_tableRows));
    _tableRows.clear();
  }

  void _emitFootnote() {
    var body = _trimBreaks(_footnote.toString());
    final candidate = _footnoteMark;
    var prefix = candidate;
    var mark = '';
    _footnote.clear();
    _footnoteMark = '';
    final echo = RegExp(r'^<sup>\s*(\S+?)\s*</sup>\s*').firstMatch(body);
    if (candidate.isNotEmpty && echo != null) {
      final fullMark = echo[1]!;
      final trimmed = candidate.trimRight();
      if (trimmed.endsWith(fullMark)) {
        prefix = trimmed.substring(0, trimmed.length - fullMark.length);
        mark = fullMark;
      } else if (fullMark.startsWith(trimmed) && trimmed.isNotEmpty) {
        prefix = '';
        mark = fullMark;
        _footnoteMarkRest = fullMark.substring(trimmed.length);
      }
      if (mark.isNotEmpty) body = body.substring(echo.end);
    }
    if (prefix.isNotEmpty) {
      _paragraph.write(
        '${_footnoteMarkTags.open}$prefix${_footnoteMarkTags.close}',
      );
    }
    if (body.isEmpty && mark.isEmpty) return;
    _paragraph.write(
      otzariaFootnote(mark.isEmpty ? '${_footnoteNumber++}' : mark, body),
    );
  }

  /// תיבת-טקסט צפה — אותה מסגרת שממיר ה-Word מייצר, כדי שהקורא יזהה אותה
  /// בלי לדעת מאיזה פורמט הגיעה.
  ///
  /// המסגרת מצוירת רק כששייף הצהיר עליה (`fLine` שאינו 0), בדיוק כמו ב-ODT:
  /// מסמך מעוצב בנוי גם מתיבות פריסה בלתי-נראות.
  void _emitTextBox() {
    final body = _trimBreaks(_textBox.toString());
    _textBox.clear();
    if (body.isEmpty) return;
    if (_shapeProperties['fLine'] == '0') {
      _paragraph.write(body);
      return;
    }
    _paragraph.write(
      '<div style="border: 1px solid #999; padding: 8px; '
      'margin: 4px 0;">$body</div>',
    );
  }

  /// [enclosing] הוא היעד שאליו חוזרים. Word עוטף כל תמונה פעמיים —
  /// `{\*\shppict …}` והעתק תאימות `{\nonshppict …}` — והשני יושב בקבוצה
  /// נבלעת; בלי הבדיקה אותה תמונה נפלטת פעמיים.
  void _emitPicture(_Destination enclosing) {
    final mime = _pictureMime;
    final hexLength = _pictureHexLength;
    _pictureMime = null;
    if (enclosing == _Destination.skip) {
      _pictureHex.clear();
      _pictureHexLength = 0;
      return;
    }
    _pictureHexLength = 0;
    final isPicture = _isPicture;
    _isPicture = false;
    if (!isPicture || hexLength < 2) {
      _pictureHex.clear();
      return;
    }
    // תמונה שחורגת מהתקרה נשארת כתג ריק, כדי שמבנה השורות יישמר.
    if (mime == null ||
        !embedImages ||
        hexLength ~/ 2 > EmbeddedMediaLimits.maxImageBytes) {
      _pictureHex.clear();
      _writeToDestination(otzariaImage(''), destination: enclosing);
      return;
    }

    final hex = _pictureHex.toString().replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    _pictureHex.clear();
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final value = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (value == null) return;
      bytes[i] = value;
    }
    _writeToDestination(
      otzariaImage('data:$mime;base64,${base64Encode(bytes)}'),
      destination: enclosing,
    );
  }

  /// בונה את ה-HTML של הטבלה, כולל מיזוגים. המיזוג האנכי נפתר רק כאן, כי
  /// הוא דורש את כל השורות: תא `\clvmgf` בולע את תאי ה-`\clvmrg` שמתחתיו.
  String _buildTableHtml(List<_RtfRow> rows) {
    // מיזוג אופקי: תא `\clmrg` מתמזג לתא שלפניו. נפתר לכל שורה בנפרד.
    final merged = <List<_RtfCell>>[];
    for (final row in rows) {
      final cells = <_RtfCell>[];
      for (final cell in row.cells) {
        if (cell.def.horizontalMergeContinue && cells.isNotEmpty) {
          cells.last.colspan++;
          if (cell.html.isNotEmpty) {
            cells.last.html = cells.last.html.isEmpty
                ? cell.html
                : '${cells.last.html}<br>${cell.html}';
          }
          continue;
        }
        cells.add(cell);
      }
      merged.add(cells);
    }

    // מיזוג אנכי: כל תא-המשך מגדיל את ה-rowspan של התא הפתוח באותה עמדה.
    for (var r = 0; r < merged.length; r++) {
      for (var c = 0; c < merged[r].length; c++) {
        final cell = merged[r][c];
        if (!cell.def.verticalMergeContinue) continue;
        for (var up = r - 1; up >= 0; up--) {
          if (c >= merged[up].length) break;
          final above = merged[up][c];
          if (above.skipped) continue;
          above.rowspan++;
          cell.skipped = true;
          break;
        }
      }
    }

    final buffer = StringBuffer();
    for (var r = 0; r < merged.length; r++) {
      final tag = rows[r].isHeader ? 'th' : 'td';
      final cells = StringBuffer();
      for (final cell in merged[r]) {
        if (cell.skipped) continue;
        final styles = <String>[otzariaTableCellStyle];
        final background = _cellBackgroundAt(cell.def.backgroundIndex);
        if (background != null) styles.add('background-color: $background');
        final vAlign = cell.def.verticalAlign;
        if (vAlign != null) styles.add('vertical-align: $vAlign');
        final attributes = StringBuffer(' style="${styles.join('; ')}"');
        if (cell.colspan > 1) attributes.write(' colspan="${cell.colspan}"');
        if (cell.rowspan > 1) attributes.write(' rowspan="${cell.rowspan}"');
        cells.write('<$tag$attributes>${cell.html}</$tag>');
      }
      if (cells.isNotEmpty) buffer.write('<tr>$cells</tr>');
    }
    final isRtl = rows.any((row) => row.isRtl);
    return '${otzariaTableOpen(attributes: isRtl ? ' dir="rtl"' : '')}'
        '$buffer</table>';
  }
}

/// מאפייני תא כפי שהוגדרו ב-`\trowd` (לפני תוכן התא).
class _RtfCellDef {
  int? backgroundIndex;
  String? verticalAlign;
  bool horizontalMergeContinue = false;
  bool verticalMergeContinue = false;
}

class _RtfCell {
  _RtfCell(this.html, this.def);

  String html;
  final _RtfCellDef def;
  int colspan = 1;
  int rowspan = 1;

  /// תא שנבלע במיזוג אנכי ואינו נפלט בפני עצמו.
  bool skipped = false;
}

class _RtfRow {
  _RtfRow(this.cells, {required this.isHeader, required this.isRtl});

  final List<_RtfCell> cells;
  final bool isHeader;
  final bool isRtl;
}

/// תא או הערה עלולים להיפתח או להיסגר ב-`\par`; מפריד שורה בקצה אינו תוכן.
String _trimBreaks(String html) => html
    .replaceAll(RegExp(r'^(?:<br>|\s)+'), '')
    .replaceAll(RegExp(r'(?:<br>|\s)+$'), '');

bool _isAlpha(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

bool _isDigit(String c) {
  final code = c.codeUnitAt(0);
  return code >= 48 && code <= 57;
}

bool _isHexDigit(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 70) ||
      (code >= 97 && code <= 102);
}
