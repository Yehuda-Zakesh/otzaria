/// שכבת המאפיינים של מסמך Word בינארי: טבלת הסגנונות (STSH), ומאפייני הפסקה
/// והתווים שיושבים ב-FKP — עמודי 512 בתים בתוך זרם `WordDocument`.
///
/// בלי השכבה הזו הממיר מפיק טקסט חשוף: אין כותרות (ולכן אין תוכן עניינים),
/// אין מודגש/נטוי, ואין טבלאות. ראו `docs/legacy_word_doc_research.md`.
library;

import 'dart:typed_data';

import 'package:otzaria/utils/text/inline_style.dart';

/// היסטי המבנים שהשכבה קוראת, מטבלת המצביעים של ה-FIB.
class LegacyWordPropertyLocations {
  final int stshOffset;
  final int stshLength;
  final int papxOffset;
  final int papxLength;
  final int chpxOffset;
  final int chpxLength;

  const LegacyWordPropertyLocations({
    required this.stshOffset,
    required this.stshLength,
    required this.papxOffset,
    required this.papxLength,
    required this.chpxOffset,
    required this.chpxLength,
  });
}

/// מאפייני פסקה. `null` בשדה = אין קביעה מפורשת.
class LegacyParagraphProperties {
  /// רמת הכותרת 1–6, אם הפסקה היא כותרת.
  final int? headingLevel;

  /// יישור מפורש. רק `center` נשמר — ראו `_alignmentFor`.
  final String? textAlign;

  /// הפסקה יושבת בתוך טבלה, ו-[isRowEnd] מסמן את סוף השורה.
  final bool inTable;
  final bool isRowEnd;

  const LegacyParagraphProperties({
    this.headingLevel,
    this.textAlign,
    this.inTable = false,
    this.isRowEnd = false,
  });

  static const LegacyParagraphProperties none = LegacyParagraphProperties();
}

/// מאפייני תווים.
class LegacyCharacterProperties {
  final bool bold;
  final bool italic;
  final bool underline;
  final UnderlineKind underlineKind;
  final bool underlineThick;
  final String? underlineColor;
  final bool strike;
  final bool doubleStrike;

  /// טקסט מוסתר (`sprmCFVanish`) — קיים במסמך ואינו אמור להיראות.
  final bool hidden;

  /// צבע הטקסט והמרקר, כערכי CSS מוכנים.
  final String? color;
  final String? highlight;

  /// `super` / `sub` / `null`.
  final String? verticalAlign;

  /// היסט התמונה בזרם `Data` (`sprmCPicLocation`), כשה-run הוא placeholder
  /// של תמונה מוטמעת.
  final int? pictureOffset;

  const LegacyCharacterProperties({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.underlineKind = UnderlineKind.single,
    this.underlineThick = false,
    this.underlineColor,
    this.strike = false,
    this.doubleStrike = false,
    this.hidden = false,
    this.color,
    this.highlight,
    this.verticalAlign,
    this.pictureOffset,
  });

  static const LegacyCharacterProperties plain = LegacyCharacterProperties();

  bool get isPlain =>
      !bold &&
      !italic &&
      !underline &&
      !strike &&
      !doubleStrike &&
      color == null &&
      highlight == null &&
      verticalAlign == null;

  /// תגי הפתיחה והסגירה, נבנים יחד כדי שיישארו מסונכרנים.
  ({String open, String close}) get tags {
    final open = StringBuffer();
    final close = <String>[];
    void wrap(({String open, String close}) pair) {
      open.write(pair.open);
      close.insert(0, pair.close);
    }

    if (bold) wrap((open: '<b>', close: '</b>'));
    if (italic) wrap((open: '<i>', close: '</i>'));
    if (underline) {
      wrap(
        underlineTags(
          kind: underlineKind,
          color: underlineColor,
          thick: underlineThick,
        ),
      );
    }
    if (strike || doubleStrike) wrap(strikeTags(doubleLine: doubleStrike));
    final marker = highlight;
    if (marker != null) wrap(highlightTags(marker));
    if (verticalAlign == 'super') wrap((open: '<sup>', close: '</sup>'));
    if (verticalAlign == 'sub') wrap((open: '<sub>', close: '</sub>'));
    final textColor = color;
    if (textColor != null) wrap(colorTags(textColor));
    return (open: open.toString(), close: close.join());
  }

  String get openTags => tags.open;

  String get closeTags => tags.close;

  @override
  bool operator ==(Object other) =>
      other is LegacyCharacterProperties &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.underlineKind == underlineKind &&
      other.underlineThick == underlineThick &&
      other.underlineColor == underlineColor &&
      other.strike == strike &&
      other.doubleStrike == doubleStrike &&
      other.hidden == hidden &&
      other.color == color &&
      other.highlight == highlight &&
      other.verticalAlign == verticalAlign &&
      other.pictureOffset == pictureOffset;

  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    underline,
    underlineKind,
    underlineThick,
    underlineColor,
    strike,
    doubleStrike,
    hidden,
    color,
    highlight,
    verticalAlign,
    pictureOffset,
  );
}

/// שאילתת מאפיינים לפי היסט (FC) בזרם `WordDocument`.
///
/// המבנים נקראים פעם אחת לטווחים ממוינים, והשאילתה היא חיפוש בינארי — היא
/// נקראת פעם אחת לכל תו במסמך.
class LegacyWordProperties {
  LegacyWordProperties._(this._paragraphs, this._characters);

  final _RangeTable<LegacyParagraphProperties> _paragraphs;
  final _RangeTable<LegacyCharacterProperties> _characters;

  /// שכבה ריקה — כשהמבנים חסרים או פגומים. הממיר ממשיך לחלץ טקסט.
  static final LegacyWordProperties empty = LegacyWordProperties._(
    _RangeTable.empty(),
    _RangeTable.empty(),
  );

  /// קורא את השכבה. **אינו זורק**: מסמך בלי FKP או עם FKP פגום מאבד עיצוב
  /// בלבד, והטקסט עצמו כבר נקרא בהצלחה מה-piece table.
  static LegacyWordProperties parse(
    Uint8List wordDocument,
    Uint8List table,
    LegacyWordPropertyLocations locations,
  ) {
    // שלושת המבנים בלתי-תלויים, ולכן כל אחד נקרא ב-try משלו: STSH פגום
    // הפיל גם את פענוח ה-PAPX/CHPX, וספר שלם איבד את כל הכותרות (ועמן את
    // תוכן העניינים), את ההדגשות ואת הטבלאות — בלי שההמרה נכשלה.
    final styles = _tryRead(
      () => _Stylesheet.parse(table, locations),
      const _Stylesheet({}),
    );
    return LegacyWordProperties._(
      _tryRead(
        () => _readFkps(
          wordDocument,
          table,
          locations.papxOffset,
          locations.papxLength,
          isParagraph: true,
          convert: (range) => _paragraphFrom(range, wordDocument, styles),
          fallback: LegacyParagraphProperties.none,
        ),
        _RangeTable<LegacyParagraphProperties>.empty(),
      ),
      _tryRead(
        () => _readFkps(
          wordDocument,
          table,
          locations.chpxOffset,
          locations.chpxLength,
          isParagraph: false,
          convert: (range) => _characterFrom(range, wordDocument),
          fallback: LegacyCharacterProperties.plain,
        ),
        _RangeTable<LegacyCharacterProperties>.empty(),
      ),
    );
  }

  static T _tryRead<T>(T Function() read, T fallback) {
    try {
      return read();
    } catch (_) {
      return fallback;
    }
  }

  LegacyParagraphProperties paragraphAt(int fc) =>
      _paragraphs.at(fc) ?? LegacyParagraphProperties.none;

  LegacyCharacterProperties characterAt(int fc) =>
      _characters.at(fc) ?? LegacyCharacterProperties.plain;

  static LegacyParagraphProperties _paragraphFrom(
    _GrpprlRange range,
    Uint8List stream,
    _Stylesheet styles,
  ) {
    if (range.length < 2) return LegacyParagraphProperties.none;
    final istd = ByteData.sublistView(
      stream,
      range.start,
      range.start + 2,
    ).getUint16(0, Endian.little);

    int? outlineLevel;
    int? jc;
    var isRtl = false;
    var inTable = false;
    var isRowEnd = false;

    for (final sprm in _sprms(stream, range.start + 2, range.end)) {
      switch (sprm.opcode) {
        case _sprmPOutLvl:
          outlineLevel = sprm.operand;
        case _sprmPJc:
        case _sprmPJc80:
          jc = sprm.operand;
        case _sprmPFBiDi:
          isRtl = sprm.operand != 0;
        case _sprmPFInTable:
          inTable = sprm.operand != 0;
        case _sprmPFTtp:
          isRowEnd = sprm.operand != 0;
      }
    }
    final textAlign = _alignmentFor(jc, isRtl: isRtl);

    // `outlineLvl` מפורש גובר על הסגנון, כמו ב-Word. 9 = "גוף טקסט".
    final level = (outlineLevel != null && outlineLevel < 9)
        ? outlineLevel + 1
        : styles.headingLevelFor(istd);

    return LegacyParagraphProperties(
      headingLevel: level?.clamp(1, 6),
      textAlign: textAlign,
      inTable: inTable,
      isRowEnd: isRowEnd,
    );
  }

  static LegacyCharacterProperties _characterFrom(
    _GrpprlRange range,
    Uint8List stream,
  ) {
    // בעברית Word כותב את וריאנט ה-Bi **לצד** הרגיל, ושניהם נושאים `0x81`
    // ("הפוך") — צבירה למשתנה אחד ביטלה את עצמה ומחקה כל הדגשה ונטייה.
    var bold = false;
    var boldBi = false;
    var italic = false;
    var italicBi = false;
    var underlineValue = 0;
    var strike = false;
    var doubleStrike = false;
    var hidden = false;
    String? color;
    String? underlineColor;
    String? highlight;
    String? verticalAlign;
    int? pictureOffset;

    for (final sprm in _sprms(stream, range.start, range.end)) {
      switch (sprm.opcode) {
        case _sprmCPicLocation:
          pictureOffset = sprm.operand32;
        case _sprmCFBold:
          bold = _toggle(sprm.operand, bold);
        case _sprmCFBoldBi:
          boldBi = _toggle(sprm.operand, boldBi);
        case _sprmCFItalic:
          italic = _toggle(sprm.operand, italic);
        case _sprmCFItalicBi:
          italicBi = _toggle(sprm.operand, italicBi);
        case _sprmCFStrike:
          strike = _toggle(sprm.operand, strike);
        case _sprmCFDStrike:
          doubleStrike = _toggle(sprm.operand, doubleStrike);
        case _sprmCFVanish:
          hidden = _toggle(sprm.operand, hidden);
        case _sprmCKul:
          underlineValue = sprm.operand;
        case _sprmCIco:
          color = cssColorForWordIndex(sprm.operand);
        case _sprmCCv:
          color = _colorRefToCss(sprm.operand32);
        case _sprmCCvUl:
          underlineColor = _colorRefToCss(sprm.operand32);
        case _sprmCHighlight:
          highlight = cssColorForWordIndex(sprm.operand, allowBlack: true);
        case _sprmCIss:
          verticalAlign = switch (sprm.operand) {
            1 => 'super',
            2 => 'sub',
            _ => null,
          };
      }
    }

    final isBold = bold || boldBi;
    final isItalic = italic || italicBi;
    final underline = underlineValue != 0 && underlineValue != _kulNone;

    if (!isBold &&
        !isItalic &&
        !underline &&
        !strike &&
        !doubleStrike &&
        !hidden &&
        color == null &&
        highlight == null &&
        verticalAlign == null &&
        pictureOffset == null) {
      return LegacyCharacterProperties.plain;
    }
    return LegacyCharacterProperties(
      bold: isBold,
      italic: isItalic,
      underline: underline,
      underlineKind: _underlineKindFor(underlineValue),
      underlineThick: _kulThick.contains(underlineValue),
      underlineColor: underlineColor,
      strike: strike,
      doubleStrike: doubleStrike,
      hidden: hidden,
      color: color,
      highlight: highlight,
      verticalAlign: verticalAlign,
      pictureOffset: pictureOffset,
    );
  }

  /// `sprmCCv` נושא `COLORREF` — סדר הבתים הוא BGR, ולא RGB.
  static String? _colorRefToCss(int? value) {
    if (value == null) return null;
    // הבית העליון הוא דגל "אוטומטי" (`0xFF`).
    if ((value >> 24) & 0xFF == 0xFF) return null;
    final r = value & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = (value >> 16) & 0xFF;
    if (r == 0 && g == 0 && b == 0) return null; // שחור = ברירת מחדל
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${hex(r)}${hex(g)}${hex(b)}';
  }

  /// sprm דו-מצבי: `0`/`1` קובעים, `0x80` יורש ו-`0x81` הופך את ערך הסגנון.
  ///
  /// **`0x81` הוא הערך שכותב Word לעיצוב ישיר**, ולא `1`: המשתמש לחץ "מודגש"
  /// על טקסט שסגנונו אינו מודגש, וההיפוך הוא הייצוג. התעלמות ממנו הותירה את
  /// כל המסמכים האמיתיים בלי שום הדגשה.
  static bool _toggle(int operand, bool current) => switch (operand) {
    0 => false,
    1 => true,
    0x81 => !current,
    _ => current,
  };

  /// יישור הפסקה, או `null` כשאין מה לסמן.
  ///
  /// בפסקה RTL נשמר **מרכוז בלבד**: Word מחליף שם את משמעות שמאל/ימין,
  /// כותב יישור כמעט בכל פסקה, והכרעה שגויה מיישרת ספר עברי שלם לצד ההפוך.
  static String? _alignmentFor(int? jc, {required bool isRtl}) {
    final align = switch (jc) {
      1 => 'center',
      0 => 'left',
      2 => 'right',
      _ => null, // 3 = דו-צדדי, וכל ערך אחר
    };
    if (align == null || align == 'center') return align;
    if (isRtl) return null;
    return align == 'left' ? null : align; // שמאל הוא הטבעי ב-LTR
  }
}

// ── טבלת טווחים ───────────────────────────────────────────────────────────

/// טווחי `[start, end)` ממוינים עם ערך לכל טווח. טווחים עשויים להיות
/// לא-רציפים, ולכן נשמרים שני מערכים ולא רשימת גבולות אחת.
class _RangeTable<T> {
  _RangeTable(this._starts, this._ends, this._values);

  _RangeTable.empty()
    : _starts = const [],
      _ends = const [],
      _values = const [];

  final List<int> _starts;
  final List<int> _ends;
  final List<T> _values;

  bool get isEmpty => _values.isEmpty;

  T? at(int position) {
    if (_values.isEmpty || position < _starts.first) return null;
    var low = 0;
    var high = _values.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (position < _starts[middle]) {
        high = middle - 1;
      } else if (position >= _ends[middle]) {
        low = middle + 1;
      } else {
        return _values[middle];
      }
    }
    return null;
  }
}

// ── טבלת הסגנונות ─────────────────────────────────────────────────────────

/// `istd` → רמת כותרת. שני מסלולי זיהוי: `sti` של סגנון מובנה (1–9 הם
/// "כותרת 1"–"כותרת 9" בכל שפה), ושם הסגנון עבור סגנון מותאם.
class _Stylesheet {
  const _Stylesheet(this._headingLevels);

  final Map<int, int> _headingLevels;

  int? headingLevelFor(int istd) => _headingLevels[istd];

  static final RegExp _headingName = RegExp(
    r'(?:heading|título|titre|überschrift|כותרת)\s*([1-9])',
    caseSensitive: false,
  );

  static _Stylesheet parse(
    Uint8List table,
    LegacyWordPropertyLocations locations,
  ) {
    final levels = <int, int>{};
    if (locations.stshLength < 8 ||
        locations.stshOffset + locations.stshLength > table.length) {
      return _Stylesheet(levels);
    }

    final stsh = ByteData.sublistView(
      table,
      locations.stshOffset,
      locations.stshOffset + locations.stshLength,
    );
    final cbStshi = stsh.getUint16(0, Endian.little);
    final cstd = stsh.getUint16(2, Endian.little);
    // האורך נקרא מהקובץ ואינו מקובע: הוא גדל בין גרסאות Word (18 ב-Word 97).
    final cbStdBase = stsh.getUint16(4, Endian.little);
    if (cbStdBase < 4) return _Stylesheet(levels);

    // `istdBase` של סגנון מותאם, לפתירת שרשרת הירושה בשלב שני.
    final bases = <int, int>{};
    var cursor = 2 + cbStshi;

    for (var istd = 0; istd < cstd; istd++) {
      if (cursor + 2 > locations.stshLength) break;
      final cbStd = stsh.getUint16(cursor, Endian.little);
      cursor += 2;
      if (cbStd == 0) continue; // משבצת פנויה — הסגנון אינו מוגדר במסמך
      // 4 ולא `cbStd`: מיד אחרי הבדיקה נקראים `sti` ו-`istdBase`, שני
      // שדות בני 2 בתים. `cbStd` בין 1 ל-3 זרק `RangeError`.
      if (cbStd < 4 || cursor + cbStd > locations.stshLength) break;

      final sti = stsh.getUint16(cursor, Endian.little) & 0x0FFF;
      final base = (stsh.getUint16(cursor + 2, Endian.little) >> 4) & 0x0FFF;
      if (base != 0x0FFF) bases[istd] = base;

      if (sti >= 1 && sti <= 9) {
        levels[istd] = sti;
      } else if (cbStdBase + 2 <= cbStd) {
        final level = _levelFromName(stsh, cursor + cbStdBase);
        if (level != null) levels[istd] = level;
      }
      cursor += cbStd;
    }

    // סגנון מותאם שמבוסס על כותרת יורש את רמתה.
    for (final istd in bases.keys) {
      if (levels.containsKey(istd)) continue;
      final seen = <int>{istd};
      var current = bases[istd];
      while (current != null && seen.add(current)) {
        final inherited = levels[current];
        if (inherited != null) {
          levels[istd] = inherited;
          break;
        }
        current = bases[current];
      }
    }

    return _Stylesheet(levels);
  }

  /// שם הסגנון הוא `Xst`: אורך בתווים ואחריו UTF-16LE.
  static int? _levelFromName(ByteData stsh, int offset) {
    if (offset + 2 > stsh.lengthInBytes) return null;
    final cch = stsh.getUint16(offset, Endian.little);
    if (cch == 0 || cch > 255 || offset + 2 + cch * 2 > stsh.lengthInBytes) {
      return null;
    }
    final units = <int>[];
    for (var i = 0; i < cch; i++) {
      units.add(stsh.getUint16(offset + 2 + i * 2, Endian.little));
    }
    final match = _headingName.firstMatch(String.fromCharCodes(units));
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

// ── FKP ───────────────────────────────────────────────────────────────────

/// קוד פורמט המספור של הערות השוליים (MSONFC), מתוך מאפייני
/// הסקציות — או `null` כשהמסמך אינו קובע אותו (issue #1239).
///
/// ב-Word 97 ומעלה הפורמט הוא מאפיין סקציה (`sprmSNfcFtnRef`) ולא שדה
/// ב-DOP: ה-DOP נושא את המקום הזה כ-`unused` מאז Word 6. הספר מוצג כרצף
/// אחד, ולכן הסקציה הראשונה שקובעת פורמט חלה על כולו.
///
/// **אינו זורק**: PLC פגום מחזיר `null` — המספור יהיה בספרות, כמו קודם.
int? legacyWordFootnoteNumberFormat(
  Uint8List stream,
  Uint8List table, {
  required int plcfSedOffset,
  required int plcfSedLength,
}) {
  // PlcfSed: (n+1) מיקומי CP בני 4 בתים ואחריהם n מבני SED בני 12 בתים.
  if (plcfSedLength <= 4 ||
      plcfSedOffset < 0 ||
      plcfSedOffset + plcfSedLength > table.length) {
    return null;
  }
  try {
    final count = (plcfSedLength - 4) ~/ 16;
    if (count <= 0) return null;
    final sedBase = plcfSedOffset + (count + 1) * 4;
    final tableView = ByteData.sublistView(table);

    for (var i = 0; i < count; i++) {
      // fcSepx הוא השדה השני ב-SED, ו-0xFFFFFFFF פירושו "לסקציה אין מאפיינים".
      final fcSepx = tableView.getUint32(sedBase + i * 12 + 2, Endian.little);
      if (fcSepx == 0xFFFFFFFF || fcSepx + 2 > stream.length) continue;

      // Sepx: `cb` בן שני בתים ואחריו grpprl באורך הזה.
      final cb = ByteData.sublistView(
        stream,
        fcSepx,
        fcSepx + 2,
      ).getUint16(0, Endian.little);
      final end = fcSepx + 2 + cb;
      if (cb <= 0 || end > stream.length) continue;

      for (final sprm in _sprms(stream, fcSepx + 2, end)) {
        if (sprm.opcode == _sprmSNfcFtnRef) return sprm.operand;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// טווח grpprl בתוך זרם `WordDocument`.
class _GrpprlRange {
  final int start;
  final int end;
  const _GrpprlRange(this.start, this.end);

  static const _GrpprlRange none = _GrpprlRange(0, 0);
  int get length => end - start;
}

const int _fkpPageSize = 512;

/// קורא את כל עמודי ה-FKP שה-PLC מפנה אליהם.
///
/// ה-PLC הוא (n+1) היסטי FC ואחריהם n מספרי עמוד. כל עמוד הוא 512 בתים בזרם
/// `WordDocument` ומכיל טבלת FC פנימית ומערך היסטים לתוך העמוד עצמו.
_RangeTable<T> _readFkps<T>(
  Uint8List stream,
  Uint8List table,
  int plcOffset,
  int plcLength, {
  required bool isParagraph,
  required T Function(_GrpprlRange range) convert,
  required T fallback,
}) {
  final starts = <int>[];
  final ends = <int>[];
  final values = <T>[];
  if (plcLength <= 4 || plcOffset + plcLength > table.length) {
    return _RangeTable.empty();
  }

  final plc = ByteData.sublistView(table, plcOffset, plcOffset + plcLength);
  final pageCount = (plcLength - 4) ~/ 8;
  final descriptorSize = isParagraph ? 13 : 1;

  for (var p = 0; p < pageCount; p++) {
    final raw = plc.getUint32((pageCount + 1) * 4 + p * 4, Endian.little);
    final page = (raw & 0x003FFFFF) * _fkpPageSize;
    if (page < 0 || page + _fkpPageSize > stream.length) continue;

    final count = stream[page + _fkpPageSize - 1];
    if (count == 0) continue;
    // טבלת ה-FC הפנימית ומערך ההיסטים חייבים להיכנס לעמוד.
    if ((count + 1) * 4 + count * descriptorSize > _fkpPageSize - 1) continue;

    final view = ByteData.sublistView(stream, page, page + _fkpPageSize);
    for (var k = 0; k < count; k++) {
      final from = view.getUint32(k * 4, Endian.little);
      final to = view.getUint32((k + 1) * 4, Endian.little);
      if (to <= from) continue;
      // FKP-ים נכתבים בסדר עולה; חריגה מסדר זו סימן לעמוד פגום.
      if (starts.isNotEmpty && from < starts.last) continue;

      final wordOffset = stream[page + (count + 1) * 4 + k * descriptorSize];
      // 0 = אין מאפיינים לרשומה; ברירות המחדל של הסגנון תופסות.
      final range = wordOffset == 0
          ? _GrpprlRange.none
          : _grpprlAt(stream, page + wordOffset * 2, page, isParagraph);

      starts.add(from);
      ends.add(to);
      values.add(range.length < 1 ? fallback : convert(range));
    }
  }

  return _RangeTable(starts, ends, values);
}

/// PAPX נושא `cb` ואחריו istd+grpprl; CHPX נושא `cb` ואחריו grpprl בלבד.
_GrpprlRange _grpprlAt(
  Uint8List stream,
  int offset,
  int page,
  bool isParagraph,
) {
  if (offset < page || offset >= page + _fkpPageSize) return _GrpprlRange.none;

  if (!isParagraph) {
    final end = offset + 1 + stream[offset];
    return end <= page + _fkpPageSize
        ? _GrpprlRange(offset + 1, end)
        : _GrpprlRange.none;
  }

  // PapxInFkp: cb!=0 → 2*cb-1 בתים; cb==0 → הבית הבא הוא cb' ואז 2*cb'.
  var cursor = offset;
  final cb = stream[cursor];
  cursor++;
  final int size;
  if (cb != 0) {
    size = cb * 2 - 1;
  } else {
    if (cursor >= page + _fkpPageSize) return _GrpprlRange.none;
    size = stream[cursor] * 2;
    cursor++;
  }
  final end = cursor + size;
  return size >= 2 && end <= page + _fkpPageSize
      ? _GrpprlRange(cursor, end)
      : _GrpprlRange.none;
}

// ── sprm ──────────────────────────────────────────────────────────────────

const int _sprmPJc80 = 0x2403;
const int _sprmPFBiDi = 0x2441;
const int _sprmPFInTable = 0x2416;
const int _sprmPFTtp = 0x2417;
const int _sprmPJc = 0x2461;
const int _sprmPOutLvl = 0x2640;

/// פורמט מספור הערות השוליים של הסקציה — אופרנד בן בית אחד (MSONFC).
const int _sprmSNfcFtnRef = 0x3009;

const int _sprmCFBold = 0x0835;
const int _sprmCFItalic = 0x0836;
const int _sprmCFStrike = 0x0837;
const int _sprmCFVanish = 0x083C;
const int _sprmCFBoldBi = 0x085C;
const int _sprmCFItalicBi = 0x085D;
const int _sprmCHighlight = 0x2A0C;
const int _sprmCKul = 0x2A3E;
const int _sprmCIco = 0x2A42;
const int _sprmCIss = 0x2A48;
const int _sprmCFDStrike = 0x2A53;
const int _sprmCPicLocation = 0x6A03;
const int _sprmCCv = 0x6870;
const int _sprmCCvUl = 0x6877;

/// ערכי `sprmCKul` (סוג הקו התחתי) לפי MS-DOC.
const int _kulNone = 0;
const int _kulDouble = 3;
const int _kulDotted = 4;
const int _kulDash = 7;
const int _kulDotDash = 9;
const int _kulDotDotDash = 10;
const int _kulWave = 11;

/// הערכים העבים. `6` הוא thick, והשאר וריאנטים כבדים של אותם סוגים.
const Set<int> _kulThick = {6, 20, 23, 24, 25, 26, 27};

UnderlineKind _underlineKindFor(int value) => switch (value) {
  _kulDouble => UnderlineKind.double,
  _kulDotted || 20 => UnderlineKind.dotted,
  _kulDash ||
  _kulDotDash ||
  _kulDotDotDash ||
  19 ||
  23 ||
  24 ||
  25 ||
  26 => UnderlineKind.dashed,
  _kulWave || 27 || 43 => UnderlineKind.wavy,
  _ => UnderlineKind.single,
};

/// sprm שנקרא מ-grpprl: אופקוד והבית הראשון של האופרנד שלו.
class _Sprm {
  final int opcode;
  final int operand;

  /// האופרנד המלא כשאורכו 4 בתים — נדרש להיסט התמונה.
  final int? operand32;

  const _Sprm(this.opcode, this.operand, [this.operand32]);
}

/// מפרק grpprl לרצף sprm-ים.
///
/// גודל האופרנד נגזר מ-`spra` (סיביות 13–15 של האופקוד) ולא מטבלה לכל אופקוד:
/// כך sprm שאינו מוכר מדולג באורך הנכון ואינו מסיט את הפענוח.
List<_Sprm> _sprms(Uint8List stream, int start, int end) {
  final result = <_Sprm>[];
  var cursor = start;
  while (cursor + 2 <= end) {
    final opcode = ByteData.sublistView(
      stream,
      cursor,
      cursor + 2,
    ).getUint16(0, Endian.little);
    cursor += 2;

    final int size;
    switch ((opcode >> 13) & 0x7) {
      case 0:
      case 1:
        size = 1;
      case 2:
      case 4:
      case 5:
        size = 2;
      case 3:
        size = 4;
      case 7:
        size = 3;
      default:
        // אורך משתנה: הבית הראשון הוא הגודל, למעט שני מבנים עם אורך 16 סיביות.
        if (opcode == 0xC615 || opcode == 0xD608) {
          if (cursor + 2 > end) return result;
          size =
              2 +
              ByteData.sublistView(
                stream,
                cursor,
                cursor + 2,
              ).getUint16(0, Endian.little);
        } else {
          if (cursor >= end) return result;
          size = 1 + stream[cursor];
        }
    }

    if (size <= 0 || cursor + size > end) return result;
    result.add(
      _Sprm(
        opcode,
        stream[cursor],
        size == 4
            ? ByteData.sublistView(
                stream,
                cursor,
                cursor + 4,
              ).getUint32(0, Endian.little)
            : null,
      ),
    );
    cursor += size;
  }
  return result;
}
