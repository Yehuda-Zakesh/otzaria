import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/legacy_word_properties.dart';
import 'package:otzaria/utils/text/inline_style.dart';

/// גודל עמוד FKP בפורמט Word הבינארי.
const int _fkpPage = 512;

/// בונה זרם `WordDocument` שבו עמוד CHPX-FKP יחיד (בעמוד 1), ואת זרם
/// ה-`Table` עם ה-PLC שמצביע אליו.
///
/// זוהי הדרך היחידה לבדוק את פענוח ה-sprm בפועל: המאפיינים אינם נגזרים
/// מהטקסט אלא מטבלת ה-FKP, ומסמך בלי FKP מחזיר תמיד "טקסט חשוף".
({Uint8List word, Uint8List table, LegacyWordPropertyLocations locations})
_buildChpxFixture(List<int> grpprl, {int from = 0, int to = 10}) {
  const page = 1;
  final word = Uint8List(_fkpPage * (page + 1));
  final base = _fkpPage * page;
  final view = ByteData.sublistView(word);

  // rgfc: שני היסטי FC (התחלה וסוף הריצה).
  view.setUint32(base, from, Endian.little);
  view.setUint32(base + 4, to, Endian.little);

  // ה-grpprl נכתב בהיסט-מילה (זוגי) בתוך העמוד, אחרי טבלת ה-FC ומערך
  // ההיסטים; 0x40 בטוח מעבר לשניהם.
  const wordOffset = 0x40;
  final chpxAt = base + wordOffset * 2;
  word[chpxAt] = grpprl.length; // cb
  word.setRange(chpxAt + 1, chpxAt + 1 + grpprl.length, grpprl);

  // rgb: בית אחד לכל רשומה — היסט-המילה של ה-CHPX שלה.
  word[base + 2 * 4] = wordOffset;
  // crun בבית האחרון של העמוד.
  word[base + _fkpPage - 1] = 1;

  // PLC: rgfc של שני ערכים ואחריו מצביע-עמוד אחד.
  final table = Uint8List(12);
  final tableView = ByteData.sublistView(table);
  tableView.setUint32(0, from, Endian.little);
  tableView.setUint32(4, to, Endian.little);
  tableView.setUint32(8, page, Endian.little);

  return (
    word: word,
    table: table,
    locations: const LegacyWordPropertyLocations(
      stshOffset: 0,
      stshLength: 0,
      papxOffset: 0,
      papxLength: 0,
      chpxOffset: 0,
      chpxLength: 12,
    ),
  );
}

/// מקודד sprm יחיד. גודל האופרנד נגזר מ-`spra` שבתוך האופקוד, בדיוק כמו
/// בפענוח.
List<int> _sprm(int opcode, int operand) {
  final bytes = <int>[opcode & 0xFF, (opcode >> 8) & 0xFF];
  switch ((opcode >> 13) & 0x7) {
    case 0:
    case 1:
      bytes.add(operand & 0xFF);
    case 2:
    case 4:
    case 5:
      bytes.addAll([operand & 0xFF, (operand >> 8) & 0xFF]);
    case 3:
      bytes.addAll([
        operand & 0xFF,
        (operand >> 8) & 0xFF,
        (operand >> 16) & 0xFF,
        (operand >> 24) & 0xFF,
      ]);
    default:
      throw ArgumentError('spra לא נתמך באופקוד $opcode');
  }
  return bytes;
}

LegacyCharacterProperties _characterFor(List<int> grpprl) {
  final fixture = _buildChpxFixture(grpprl);
  return LegacyWordProperties.parse(
    fixture.word,
    fixture.table,
    fixture.locations,
  ).characterAt(0);
}

/// אותו מבנה עמוד, אבל ל-PAPX: לכל רשומה 13 בתים (היסט + PHE), וה-grpprl
/// נפתח ב-`istd` ובאורך מקודד (`PapxInFkp`).
LegacyParagraphProperties _paragraphFor(List<int> grpprl, {int istd = 0}) {
  const page = 1;
  final word = Uint8List(_fkpPage * (page + 1));
  final base = _fkpPage * page;
  final view = ByteData.sublistView(word);

  view.setUint32(base, 0, Endian.little);
  view.setUint32(base + 4, 10, Endian.little);

  const wordOffset = 0x40;
  final papxAt = base + wordOffset * 2;
  final payload = <int>[istd & 0xFF, (istd >> 8) & 0xFF, ...grpprl];
  var cursor = papxAt;
  if (payload.length.isOdd) {
    word[cursor++] = (payload.length + 1) ~/ 2; // cb → 2*cb-1 בתים
  } else {
    word[cursor++] = 0; // הצורה הארוכה: cb=0 ואז cb' → 2*cb' בתים
    word[cursor++] = payload.length ~/ 2;
  }
  word.setRange(cursor, cursor + payload.length, payload);

  word[base + 2 * 4] = wordOffset;
  word[base + _fkpPage - 1] = 1;

  final table = Uint8List(12);
  final tableView = ByteData.sublistView(table);
  tableView.setUint32(0, 0, Endian.little);
  tableView.setUint32(4, 10, Endian.little);
  tableView.setUint32(8, page, Endian.little);

  return LegacyWordProperties.parse(
    word,
    table,
    const LegacyWordPropertyLocations(
      stshOffset: 0,
      stshLength: 0,
      papxOffset: 0,
      papxLength: 12,
      chpxOffset: 0,
      chpxLength: 0,
    ),
  ).paragraphAt(0);
}

// אופקודי ה-sprm שהבדיקות משתמשות בהם.
const _cfBold = 0x0835;
const _cfItalic = 0x0836;
const _cfStrike = 0x0837;
const _cfVanish = 0x083C;
const _cfBoldBi = 0x085C;
const _cfItalicBi = 0x085D;
const _cHighlight = 0x2A0C;
const _cKul = 0x2A3E;
const _cIco = 0x2A42;
const _cfDStrike = 0x2A53;
const _cCv = 0x6870;

/// הערך ש-Word כותב לעיצוב ישיר: "הפוך את מה שהסגנון קבע".
const _toggle = 0x81;

void main() {
  group('מודגש/נטוי בעברית — וריאנט ה-Bi', () {
    test('הווריאנט הרגיל לבדו', () {
      expect(_characterFor(_sprm(_cfBold, _toggle)).bold, isTrue);
      expect(_characterFor(_sprm(_cfItalic, _toggle)).italic, isTrue);
    });

    test('וריאנט ה-Bi לבדו', () {
      expect(_characterFor(_sprm(_cfBoldBi, _toggle)).bold, isTrue);
      expect(_characterFor(_sprm(_cfItalicBi, _toggle)).italic, isTrue);
    });

    test('שני הווריאנטים יחד — כפי ש-Word כותב לטקסט עברי', () {
      // שניהם נושאים 0x81 ("הפוך"); צבירה למשתנה אחד ביטלה את עצמה, וכל
      // ההדגשה והנטייה בעברית נעלמו מכל מסמך .doc.
      final both = _characterFor([
        ..._sprm(_cfBold, _toggle),
        ..._sprm(_cfBoldBi, _toggle),
        ..._sprm(_cfItalic, _toggle),
        ..._sprm(_cfItalicBi, _toggle),
      ]);
      expect(both.bold, isTrue);
      expect(both.italic, isTrue);
      expect(both.tags.open, startsWith('<b><i>'));
    });

    test('ביטול מפורש (0) גובר על הווריאנט השני', () {
      final off = _characterFor([
        ..._sprm(_cfBold, 0),
        ..._sprm(_cfBoldBi, 0),
      ]);
      expect(off.bold, isFalse);
      expect(off.isPlain, isTrue);
    });
  });

  group('מאפייני תווים נוספים', () {
    test('טקסט מוסתר מסומן ואינו נפלט', () {
      expect(_characterFor(_sprm(_cfVanish, _toggle)).hidden, isTrue);
    });

    test('קו חוצה יחיד וכפול', () {
      expect(_characterFor(_sprm(_cfStrike, _toggle)).strike, isTrue);
      expect(
        _characterFor(_sprm(_cfDStrike, _toggle)).tags.open,
        contains('line-through double'),
      );
    });

    test('סוגי קו תחתי לפי sprmCKul', () {
      expect(_characterFor(_sprm(_cKul, 1)).underline, isTrue);
      expect(
        _characterFor(_sprm(_cKul, 3)).underlineKind,
        UnderlineKind.double,
      );
      expect(
        _characterFor(_sprm(_cKul, 4)).underlineKind,
        UnderlineKind.dotted,
      );
      expect(
        _characterFor(_sprm(_cKul, 7)).underlineKind,
        UnderlineKind.dashed,
      );
      expect(_characterFor(_sprm(_cKul, 11)).underlineKind, UnderlineKind.wavy);
      expect(_characterFor(_sprm(_cKul, 6)).underlineThick, isTrue);
      expect(_characterFor(_sprm(_cKul, 0)).underline, isFalse);
    });

    test('צבע לפי אינדקס הפלטה — שחור אינו נפלט', () {
      expect(_characterFor(_sprm(_cIco, 6)).color, 'red');
      expect(_characterFor(_sprm(_cIco, 1)).color, isNull); // שחור
      expect(_characterFor(_sprm(_cIco, 0)).color, isNull); // אוטומטי
    });

    test('צבע מלא (COLORREF) הוא BGR ולא RGB', () {
      // 0x000000C0 = R=0xC0, G=0, B=0 → אדום כהה.
      expect(_characterFor(_sprm(_cCv, 0x000000C0)).color, '#c00000');
      // הבית העליון 0xFF מסמן "אוטומטי".
      expect(_characterFor(_sprm(_cCv, 0xFF000000)).color, isNull);
    });

    test('מרקר — שחור כן נשמר, כי הוא בחירה של המחבר', () {
      expect(_characterFor(_sprm(_cHighlight, 7)).highlight, 'yellow');
      expect(_characterFor(_sprm(_cHighlight, 1)).highlight, 'black');
      expect(_characterFor(_sprm(_cHighlight, 0)).highlight, isNull);
    });

    test('אין מאפיינים → plain, בלי תגיות מיותרות', () {
      expect(_characterFor(const []).isPlain, isTrue);
      expect(_characterFor(const []).tags.open, isEmpty);
    });
  });

  group('יישור פסקה מול כיוונה', () {
    const jc80 = 0x2403;
    const pfBiDi = 0x2441;
    const jcLeft = 0;
    const jcCenter = 1;
    const jcRight = 2;
    const jcBoth = 3;

    test('מרכוז נשמר תמיד', () {
      expect(_paragraphFor(_sprm(jc80, jcCenter)).textAlign, 'center');
    });

    test('בפסקה LTR: שמאל הוא הטבעי ואינו נכתב, ימין כן', () {
      expect(_paragraphFor(_sprm(jc80, jcLeft)).textAlign, isNull);
      expect(_paragraphFor(_sprm(jc80, jcRight)).textAlign, 'right');
    });

    test('בפסקה RTL נשמר מרכוז בלבד', () {
      // Word מחליף שם את משמעות שמאל/ימין, והכרעה שגויה מיישרת ספר עברי
      // שלם לצד ההפוך.
      List<int> rtl(int jc) => [..._sprm(pfBiDi, 1), ..._sprm(jc80, jc)];
      expect(_paragraphFor(rtl(jcRight)).textAlign, isNull);
      expect(_paragraphFor(rtl(jcLeft)).textAlign, isNull);
      expect(_paragraphFor(rtl(jcCenter)).textAlign, 'center');
    });

    test('יישור דו-צדדי אינו נכתב', () {
      expect(_paragraphFor(_sprm(jc80, jcBoth)).textAlign, isNull);
    });
  });

  group('חוזה התגיות', () {
    test('הפתיחה והסגירה מקוננות נכון', () {
      final props = _characterFor([
        ..._sprm(_cfBold, _toggle),
        ..._sprm(_cfItalic, _toggle),
        ..._sprm(_cIco, 6),
      ]);
      expect(props.tags.open, '<b><i><span style="color:red">');
      expect(props.tags.close, '</span></i></b>');
    });
  });
}
