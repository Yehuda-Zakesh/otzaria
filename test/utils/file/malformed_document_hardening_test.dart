import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/cfb_reader.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';
import 'package:otzaria/utils/file/legacy_word_to_otzaria.dart';
import 'package:otzaria/utils/file/odt_to_otzaria.dart';
import 'package:otzaria/utils/file/rtf_to_otzaria.dart';

import 'cfb_fixtures.dart';

/// קובץ פגום, קטוע או זדוני חייב להיכשל **בקול** ובחריגה מוקלדת.
///
/// מצב הכשל הגרוע ביותר בצנרת הזו אינו קריסה אלא ההפך: פלט חלקי שנראה כמו
/// ספר תקין. הוא נשמר במטמון ל-90 יום, נכנס לאינדקס, ומסמן כל הערה אישית
/// שמעבר לשורה האחרונה שנקראה כחסרה — לצמיתות.

/// תווי הבקרה של שדה ב-MS-DOC. נבנים מקוד ולא כתו בקובץ, כדי שהמקור יישאר
/// קריא ולא יישבר בעריכה.
final String _fieldBegin = String.fromCharCode(0x13);
final String _fieldSeparator = String.fromCharCode(0x14);
final String _fieldEnd = String.fromCharCode(0x15);
final String _paragraphEnd = String.fromCharCode(0x0D);

/// פקודת RTF, נבנית כדי שהמקור לא יכיל escapes דו-משמעיים.
String _rtfWord(String word, [String parameter = '']) => '\\$word$parameter';

/// `\*` — מסמן יעד שאפשר להתעלם ממנו.
final String _rtfIgnorable = '\\*';

/// ההיסט של המופע האחרון של [signature] בבייטים, או `null`.
int? _lastIndexOfSignature(Uint8List bytes, List<int> signature) {
  outer:
  for (var i = bytes.length - signature.length; i >= 0; i--) {
    for (var j = 0; j < signature.length; j++) {
      if (bytes[i + j] != signature[j]) continue outer;
    }
    return i;
  }
  return null;
}

/// `\'hh` — בית בדף-הקוד הנוכחי.
String _rtfByte(String hex) => "\\'$hex";

Uint8List _rtfBytes(String source) => Uint8List.fromList(latin1.encode(source));

/// בונה מכולת CFB ובה [slotCount] משבצות ספרייה, שכל אחת מפנה לבאה אחריה
/// ב-`leftId` — כלומר עץ שהוא שרשרת ליניארית בעומק `slotCount - 1`.
///
/// כל הזרמים ריקים; הנבדק הוא ההליכה על העץ ולא קריאת התוכן.
Uint8List _cfbWithLinearDirectoryChain(int slotCount) {
  const sectorSize = 512;
  const entrySize = 128;
  const fatSect = 0xFFFFFFFD;
  const endOfChain = 0xFFFFFFFE;
  const free = 0xFFFFFFFF;

  final directorySectors = (slotCount * entrySize) ~/ sectorSize;
  final fatSectorCount = ((directorySectors + 8) / (sectorSize ~/ 4)).ceil();
  final totalSectors = fatSectorCount + directorySectors;

  final bytes = Uint8List(sectorSize * (1 + totalSectors));
  final view = ByteData.sublistView(bytes);

  // ── כותר ──
  bytes.setRange(0, 8, CfbBuilder.signature);
  view
    ..setUint16(0x18, 0x003E, Endian.little) // minor version
    ..setUint16(0x1A, 0x0003, Endian.little) // major version
    ..setUint16(0x1C, 0xFFFE, Endian.little) // byte order
    ..setUint16(0x1E, 9, Endian.little) // sector shift
    ..setUint16(0x20, 6, Endian.little) // mini sector shift
    ..setUint32(0x2C, fatSectorCount, Endian.little)
    ..setUint32(0x30, fatSectorCount, Endian.little) // first directory sector
    ..setUint32(0x38, 0x1000, Endian.little) // mini stream cutoff
    ..setUint32(0x3C, endOfChain, Endian.little) // first miniFAT sector
    ..setUint32(0x44, endOfChain, Endian.little) // first DIFAT sector
    ..setUint32(0x48, 0, Endian.little);
  for (var i = 0; i < 109; i++) {
    view.setUint32(0x4C + i * 4, i < fatSectorCount ? i : free, Endian.little);
  }

  // ── FAT: סקטורי ה-FAT עצמם, ואחריהם שרשרת סקטורי הספרייה ──
  int sectorOffset(int sector) => (sector + 1) * sectorSize;
  const entriesPerFatSector = sectorSize ~/ 4;
  final fatCapacity = fatSectorCount * entriesPerFatSector;
  for (var i = 0; i < fatCapacity; i++) {
    final slotAddress =
        sectorOffset(i ~/ entriesPerFatSector) + (i % entriesPerFatSector) * 4;
    final value = i < fatSectorCount
        ? fatSect
        : i < totalSectors
        ? (i == totalSectors - 1 ? endOfChain : i + 1)
        : free;
    view.setUint32(slotAddress, value, Endian.little);
  }

  // ── ספרייה: שורש ואחריו שרשרת `leftId` ──
  final directoryBase = sectorOffset(fatSectorCount);
  void writeEntry(
    int slot,
    String name, {
    required int type,
    int left = free,
    int right = free,
    int child = free,
  }) {
    final base = directoryBase + slot * entrySize;
    for (var i = 0; i < name.length; i++) {
      view.setUint16(base + i * 2, name.codeUnitAt(i), Endian.little);
    }
    view
      ..setUint16(base + 64, (name.length + 1) * 2, Endian.little)
      ..setUint32(base + 68, left, Endian.little)
      ..setUint32(base + 72, right, Endian.little)
      ..setUint32(base + 76, child, Endian.little)
      ..setUint32(base + 116, endOfChain, Endian.little)
      ..setUint32(base + 120, 0, Endian.little);
    bytes[base + 66] = type;
  }

  writeEntry(0, 'Root Entry', type: 5, child: 1);
  for (var slot = 1; slot < slotCount; slot++) {
    writeEntry(
      slot,
      's$slot',
      type: 2,
      left: slot + 1 < slotCount ? slot + 1 : free,
    );
  }

  return bytes;
}

void main() {
  group('CFB — שרשרות סקטורים', () {
    test('זרם שנחתך באמצע זורק ואינו מחזיר תוכן חלקי', () {
      // 8KB = 16 סקטורים, כדי שהחיתוך יפגע באמצע השרשרת ולא בכותר.
      final bytes = CfbBuilder({'WordDocument': Uint8List(8192)}).build();
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 512);

      expect(
        () => CfbFile.parse(truncated).readStream('WordDocument'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('זרם קצר (mini stream) שנחתך זורק אף הוא', () {
      final bytes = CfbBuilder({'Short': Uint8List(32)}).build();
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 512);

      expect(
        () => CfbFile.parse(truncated).readStream('Short'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('CFB — כותר משקר', () {
    /// עוקף את הבונה כדי לשקר בשדה בודד בכותר.
    Uint8List withHeaderField(int offset, int value) {
      final bytes = CfbBuilder({'WordDocument': Uint8List(64)}).build();
      ByteData.sublistView(bytes).setUint32(offset, value, Endian.little);
      return bytes;
    }

    test('mini stream cutoff מזויף אינו משפיע על הקריאה', () {
      // המפרט מקבע את הערך, ולכן הוא נלקח מקבוע ולא מהכותר: ערך מזויף היה
      // מפנה *כל* זרם למקום הלא נכון, ואכיפתו הייתה דוחה קובץ תקין לגמרי.
      for (final lie in [0, 0x200, 0x2000]) {
        final cfb = CfbFile.parse(withHeaderField(0x38, lie));
        expect(cfb.readStream('WordDocument'), hasLength(64), reason: '$lie');
      }
    });

    test('מספר סקטורי FAT מופרך נדחה ואינו מנפח את הזיכרון', () {
      // כל סקטור FAT מוסיף 128 כניסות; בלי חסימה, כותר שמצהיר על מיליוני
      // סקטורים בונה טבלה של ג'יגה-בייטים לפני שמישהו קורא ממנה.
      expect(
        () => CfbFile.parse(withHeaderField(0x2C, 0x00FFFFFF)),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('CFB — עומק עץ הספריות', () {
    test('שרשרת אחים ליניארית בת 20,000 אינה מקריסה את המחסנית', () {
      // עומק ההליכה על העץ שווה לאורך שרשרת ה-`leftId`, ורקורסיה נפלה כאן.
      // המכולה נבנית ידנית ולא ב-CfbBuilder: הוא בונה עץ מאוזן, שאינו מגיע
      // לעומק הזה בשום מספר זרמים.
      final bytes = _cfbWithLinearDirectoryChain(20000);

      expect(CfbFile.parse(bytes).streamNames, hasLength(19999));
      expect(isLegacyWordContainer(bytes), isFalse);
    });
  });

  group('Word בינארי — שדות', () {
    /// גוף המסמך (בלי שורת ה-`<h1>`), כפסקאות מופרדות ברווח.
    String bodyOf(String text) => legacyWordToText(
      buildWordBinary([WordPiece(text, compressed: true)]),
      'T',
    ).split('\n').skip(1).join(' ');

    test('שדה מקונן אינו מדליף את ההוראה החיצונית לגוף', () {
      // `IF { PAGE } = 7 "yes" "no"` — דגל בוליאני יחיד היה נסגר על ה-\\14
      // של השדה הפנימי, ומכאן ההוראה החיצונית זולגת לטקסט.
      final text =
          'A$_fieldBegin IF $_fieldBegin PAGE $_fieldSeparator'
          '7$_fieldEnd = 7 "yes" "no" $_fieldSeparator'
          'RESULT${_fieldEnd}B$_paragraphEnd';

      expect(bodyOf(text), 'ARESULTB');
    });

    test('שדה שאינו נסגר בולע עד סוף הפסקה בלבד', () {
      final text =
          'lifney$_fieldBegin'
          'nivla$_paragraphEnd'
          'acharey$_paragraphEnd';

      final body = bodyOf(text);
      expect(body, contains('lifney'));
      expect(body, contains('acharey'));
      expect(body, isNot(contains('nivla')));
    });

    test('חתיכה שהיסטה חורג מהזרם זורקת ואינה משמיטה פסקה בשקט', () {
      final bytes = buildWordBinary([
        const WordPiece('שלום עולם'),
        const WordPiece('פסקה שנייה'),
      ], outOfRangePiece: 1);

      expect(
        () => legacyWordToText(bytes, 'T'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('RTF — קלט מעוות אינו זורק חריגה לא מוקלדת', () {
    test('בית הקסדצימלי עם סימן אינו מקריס את הפענוח', () {
      // `int.tryParse` מקבל סימן, ובית שלילי הפיל את `String.fromCharCode`
      // ב-RangeError — חריגה שאינה DocumentConversionException.
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')}'
          '${_rtfWord('ansicpg', '1255')} abc${_rtfByte('-f')} def}';

      expect(rtfToText(_rtfBytes(source), 'T'), contains('abc'));
    });

    test('נקודת קוד מחוץ לטווח מדולגת ואינה זורקת RangeError', () {
      for (final parameter in ['1114112', '-100000']) {
        // `?` הוא תו-הגיבוי של `\uN` ונבלע כמתוכנן; "end" מוכיח שהפענוח
        // המשיך מהמקום הנכון ולא נקטע.
        final source =
            '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')} '
            '${_rtfWord('u', parameter)} ?end}';

        expect(
          rtfToText(_rtfBytes(source), 'T'),
          contains('end'),
          reason: parameter,
        );
      }
    });

    test('מטען בינארי מדולג ואינו פורק את מחסנית הקבוצות', () {
      // ששת ה-`}` הם המטען של `\bin6`, לא תחביר.
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')} '
          '${_rtfWord('bin', '6')} }}}}}} after}';

      expect(rtfToText(_rtfBytes(source), 'T'), contains('after'));
    });
  });

  group('RTF — גבולות פסקה', () {
    test('שבירת פסקה בתוך תא טבלה היא מפריד שורה ולא מחיקה', () {
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')}'
          '${_rtfWord('trowd')}${_rtfWord('intbl')} ALEF${_rtfWord('par')} '
          'BET${_rtfWord('cell')}${_rtfWord('row')}}';

      expect(rtfToText(_rtfBytes(source), 'T'), contains('ALEF<br>BET'));
    });

    test('שבירת פסקה בתוך הערת שוליים אינה מפצלת את פסקת הגוף', () {
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')} before'
          '{${_rtfWord('footnote')} first${_rtfWord('par')} second}'
          'after${_rtfWord('par')}}';

      final body = rtfToText(_rtfBytes(source), 'T').split('\n').skip(1);

      expect(body, hasLength(1));
      expect(body.single, contains('first<br>second'));
      expect(body.single, matches(RegExp('before.*after')));
    });

    test('שורת טבלה ריקה אינה מקריסה את שאר הספר לשורה אחת', () {
      // `_inTable` שנתקע דלוק הופך כל `\par` שאחריו ל-`<br>`, וכל המסמך
      // מתמזג לשורה אחת — בלי תוכן עניינים, בלי עיגון הערות.
      final source = StringBuffer(
        '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')}'
        '${_rtfWord('trowd')}${_rtfWord('cellx', '1000')}'
        '${_rtfWord('pard')}${_rtfWord('intbl')}${_rtfWord('row')} '
        '${_rtfWord('pard')} ',
      );
      for (var i = 1; i <= 20; i++) {
        source.write('P$i${_rtfWord('par')} ');
      }
      source.write('}');

      final lines = rtfToText(_rtfBytes(source.toString()), 'T').split('\n');

      expect(lines, hasLength(21)); // h1 + 20 פסקאות
      expect(lines.last, contains('P20'));
    });

    test('שורת טבלה ריקה אינה מייצרת טבלת פנטום בפלט', () {
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')}'
          '${_rtfWord('pard')} P1${_rtfWord('par')}'
          '{${_rtfWord('stylesheet')}{${_rtfWord('s', '1')} '
          '${_rtfWord('cell')} x;}}'
          'P2${_rtfWord('par')}}';

      final text = rtfToText(_rtfBytes(source), 'T');

      expect(text, contains('P1'));
      expect(text, contains('P2'));
      expect(text, isNot(contains('<table')));
    });

    test('`\\cell` בתוך הערת שוליים אינו גוזל את פסקת הגוף', () {
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')} ROW1TEXT'
          '{${_rtfWord('footnote')} ${_rtfWord('pard')} XA'
          '${_rtfWord('cell')} XB${_rtfWord('cell')}${_rtfWord('row')}} '
          'TAIL${_rtfWord('par')}}';

      final text = rtfToText(_rtfBytes(source), 'T');

      expect(text, isNot(contains('<td')));
      expect(text, matches(RegExp('ROW1TEXT.*TAIL', dotAll: true)));
    });

    test('יעד שלא נסגר אינו מוחק את שאר המסמך', () {
      // `\par` בתוך `\listtext`/`\footnote` שלא נסגרו פירושו קובץ קטוע;
      // התעלמות מהם מחקה את כל מה שאחריהם.
      final unclosedNote =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')} A'
          '{${_rtfWord('footnote')} note P1${_rtfWord('par')} '
          'P2${_rtfWord('par')} P3${_rtfWord('par')}';
      final unclosedLabel =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')}${_rtfWord('pard')}'
          '{$_rtfIgnorable${_rtfWord('listtext')} 1. '
          'P1${_rtfWord('par')} P2${_rtfWord('par')} P3${_rtfWord('par')}';

      expect(rtfToText(_rtfBytes(unclosedNote), 'T'), contains('P3'));
      expect(rtfToText(_rtfBytes(unclosedLabel), 'T'), contains('P3'));
    });

    test('שורת טבלה שה-row שלה חסר אינה נעלמת', () {
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')} '
          'x${_rtfWord('cell')} y${_rtfWord('par')}}';

      final text = rtfToText(_rtfBytes(source), 'T');

      expect(text, contains('x'));
      expect(text, contains('y'));
    });
  });

  group('RTF — דף-קוד לפי גופן', () {
    test('charset עברי גובר על דף-קוד לטיני מוצהר', () {
      // כך Word שומר מסמך עברי: ansicpg1252 בכותרת, fcharset177 בגופן.
      final source =
          '{${_rtfWord('rtf', '1')}${_rtfWord('ansi')}'
          '${_rtfWord('ansicpg', '1252')}'
          '{${_rtfWord('fonttbl')}{${_rtfWord('f', '0')}'
          '${_rtfWord('fcharset', '177')} David;}}'
          '${_rtfWord('f', '0')} '
          '${_rtfByte('e0')}${_rtfByte('e1')}${_rtfByte('e2')}}';

      expect(rtfToText(_rtfBytes(source), 'T'), contains('אבג'));
    });
  });

  group('ODT — הזרקת HTML ממסמך חיצוני', () {
    Uint8List odt(String contentXml) {
      final bytes = utf8.encode(contentXml);
      final archive = Archive()
        ..addFile(ArchiveFile('content.xml', bytes.length, bytes));
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    String contentWith(String styleXml, String bodyXml) =>
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-content '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:'
        'xsl-fo-compatible:1.0" '
        'xmlns:xlink="http://www.w3.org/1999/xlink">'
        '<office:automatic-styles>$styleXml</office:automatic-styles>'
        '<office:body><office:text>$bodyXml</office:text></office:body>'
        '</office:document-content>';

    test('צבע טקסט אינו יכול לסגור את המאפיין ולהוסיף תגיות', () {
      final malicious =
          'red;">&lt;img src=x onerror=alert(1)&gt;&lt;span style="a';
      final bytes = odt(
        contentWith(
          '<style:style style:name="C1" style:family="text">'
              '<style:text-properties fo:color=\'$malicious\'/>'
              '</style:style>',
          '<text:p><text:span text:style-name="C1">טקסט</text:span></text:p>',
        ),
      );

      final text = odtToText(bytes, 'T');

      expect(text, contains('טקסט'));
      // ערך שאינו צבע CSS תקין נדחה כליל, ולכן אין `style` להיחלץ ממנו.
      expect(text, isNot(contains('<img')));
      expect(text, isNot(contains('style=')));
    });

    test('כתובת קישור אינה יכולה להוסיף מאפיינים לתגית העוגן', () {
      final bytes = odt(
        contentWith(
          '',
          '<text:p><text:a xlink:href=\'x" onmouseover="bad\'>'
              'link</text:a></text:p>',
        ),
      );

      final text = odtToText(bytes, 'T');

      expect(text, contains('link'));
      expect(text, isNot(contains('onmouseover="bad"')));
    });

    test('קינון עמוק אינו מקריס את המחסנית ואינו מאבד את הטקסט', () {
      const depth = 3000;
      final body =
          '<text:p>${'<text:span>' * depth}עמוק'
          '${'</text:span>' * depth}</text:p>';

      expect(odtToText(odt(contentWith('', body)), 'T'), contains('עמוק'));
    });
  });

  // HTML הוא הפורמט היחיד שאוצריא קולטת ושהמשתמש מוריד מהאינטרנט כדבר
  // שבשגרה, ולכן קלט **עוין** הוא מקרה הקצה הצפוי שלו ולא החריג.
  group('HTML — קלט עוין', () {
    Uint8List html(String body) =>
        Uint8List.fromList(utf8.encode('<html><body>$body</body></html>'));

    test('מכולה בינארית בסיומת HTML נכשלת ואינה נקראת כטקסט', () {
      // ZIP שפוענח כ-Windows-1255 מייצר ג'יבריש עברי שנראה כספר תקין.
      expect(
        () => htmlToText(
          Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xE0, 0xE1, 0xE2]),
          'T',
        ),
        throwsA(isA<UnsupportedDocumentFormatException>()),
      );
    });

    test('סקריפט ומטפלי אירועים אינם מגיעים לגוף הספר', () {
      final text = htmlToText(
        html(
          '<script>fetch("https://evil.example")</script>'
          '<p onclick="steal()" onerror="x()">טקסט</p>',
        ),
        'T',
      );
      expect(text, contains('טקסט'));
      expect(text, isNot(contains('evil.example')));
      expect(text, isNot(contains('onclick')));
      expect(text, isNot(contains('onerror')));
    });

    test('ערך style אינו יכול לסגור את המאפיין ולהוסיף תגיות', () {
      final text = htmlToText(
        html(
          '<p><span style=\'color: red;"&gt;&lt;img src=x '
          'onerror=alert(1)&gt;&lt;span style="a\'>טקסט</span></p>',
        ),
        'T',
      );
      expect(text, contains('טקסט'));
      expect(text, isNot(contains('<img')));
      expect(text, isNot(contains('onerror')));
    });

    test('כתובת קישור אינה יכולה להוסיף מאפיינים לתגית העוגן', () {
      final text = htmlToText(
        html(
          '<p><a href=\'https://a.example/x" onmouseover="bad\'>link</a>'
          '</p>',
        ),
        'T',
      );
      expect(text, contains('link'));
      expect(text, isNot(contains('onmouseover="bad"')));
    });

    test('קינון עמוק אינו מקריס את המחסנית', () {
      const depth = 3000;
      expect(
        () => htmlToText(
          html('<p>${'<span>' * depth}עמוק${'</span>' * depth}</p>'),
          'T',
        ),
        returnsNormally,
      );
    });

    test('מסמך מעל תקרת הגודל נכשל לפני הפרסינג', () {
      expect(
        () => htmlToText(Uint8List(HtmlLimits.maxSourceBytes + 1), 'T'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('חבילה מוצפנת מדווחת כמוצפנת ולא כפגומה', () {
    test('DOCX מוצפן (מכולת OLE) זורק EncryptedDocumentException', () {
      // OOXML מוצפן אינו ZIP אלא מכולת OLE עם זרם EncryptedPackage.
      final bytes = CfbBuilder({
        'EncryptedPackage': Uint8List(128),
        'EncryptionInfo': Uint8List(64),
      }).build();

      expect(
        () => docxToText(bytes, 'מוצפן'),
        throwsA(isA<EncryptedDocumentException>()),
      );
    });

    test('ODT מוגן בסיסמה זורק EncryptedDocumentException', () {
      final manifest = utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:'
        'opendocument:xmlns:manifest:1.0">'
        '<manifest:file-entry manifest:full-path="content.xml">'
        '<manifest:encryption-data manifest:checksum="x"/>'
        '</manifest:file-entry></manifest:manifest>',
      );
      final content = utf8.encode('בייטים מוצפנים');
      final archive = Archive()
        ..addFile(
          ArchiveFile('META-INF/manifest.xml', manifest.length, manifest),
        )
        ..addFile(ArchiveFile('content.xml', content.length, content));

      expect(
        () => odtToText(Uint8List.fromList(ZipEncoder().encode(archive)), 'מ'),
        throwsA(isA<EncryptedDocumentException>()),
      );
    });
  });

  group('חריגה מוקלדת גם על קלט שמפיל את מפענח ה-ZIP', () {
    test('DOCX עם זרם deflate מקולקל אינו זורק RangeError', () {
      // `RangeError` אינו DocumentConversionException ולכן בורח מכל מטפל
      // בצנרת — ספר פגום אחד היה מפיל את סריקת האינדוקס כולה.
      final documentXml = utf8.encode(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>'
        '${'תוכן ' * 200}</w:t></w:r></w:p></w:body></w:document>',
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile('word/document.xml', documentXml.length, documentXml),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      for (var i = 200; i < 260 && i < bytes.length; i++) {
        bytes[i] = ~bytes[i] & 0xFF;
      }

      expect(
        () => docxToText(bytes, 'פגום'),
        throwsA(isA<DocumentConversionException>()),
      );
    });

    test('רשומה שהצהירה קטן ונפרסה גדול נדחית', () {
      // הגודל ברשומת ה-ZIP הוא הצהרה של הקובץ, והפריסה אינה חסומה לפיו.
      final documentXml = utf8.encode(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>'
        '${'א' * 60000}</w:t></w:r></w:p></w:body></w:document>',
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile('word/document.xml', documentXml.length, documentXml),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      // ה-uncompressed size מוצהר גם ב-local header (היסט 22) וגם ב-central
      // directory; מזייפים אותו לערך זעיר בשניהם.
      final view = ByteData.sublistView(bytes);
      view.setUint32(22, 4096, Endian.little);
      final centralDirectory = _lastIndexOfSignature(bytes, [
        0x50,
        0x4B,
        0x01,
        0x02,
      ]);
      expect(centralDirectory, isNotNull);
      view.setUint32(centralDirectory! + 24, 4096, Endian.little);

      expect(
        () => docxToText(bytes, 'שקרן'),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });
  });

  group('fileType ברירת-מחדל אינו דורס סיומת אמיתית', () {
    test('רשומת DB שנשארה על txt אינה קובעת עבור קובץ docx', () {
      // `fileType TEXT DEFAULT 'txt'` הוא ברירת מחדל של העמודה ולא הצהרה.
      // בלי החריג הזה מכולת ZIP נקראת כ-Windows-1255 — ג'יבריש שנראה תקין.
      expect(
        documentFormatOf(fileType: 'txt', path: 'ספר.docx'),
        DocumentFormat.docx,
      );
      expect(
        documentFormatOf(fileType: 'txt', path: 'ספר.doc'),
        DocumentFormat.doc,
      );
      // הצהרה שאינה ברירת המחדל כן גוברת — ספר DOCX שנשמר בסיומת txt.
      expect(
        documentFormatOf(fileType: 'docx', path: 'מוסווה.txt'),
        DocumentFormat.docx,
      );
      expect(
        documentFormatOf(fileType: 'txt', path: 'ספר.txt'),
        DocumentFormat.txt,
      );
    });
  });

  group('זיהוי-תוכן קורא גם את זנב הקובץ', () {
    test('DOCX שנפתח בתמונה גדולה מזוהה מה-central directory', () {
      // שמות הרשומות מרוכזים בסוף החבילה. זיהוי מהראש בלבד החזיר null,
      // וה-ZIP נקרא כטקסט — ג'יבריש עברי שנראה כספר תקין לגמרי.
      final image = Uint8List(1600 * 1024);
      var state = 12345;
      for (var i = 0; i < image.length; i++) {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        image[i] = (state >> 16) & 0xFF;
      }
      final documentXml = utf8.encode(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/'
        'wordprocessingml/2006/main"><w:body/></w:document>',
      );
      final archive = Archive()
        ..addFile(ArchiveFile('word/media/image1.bin', image.length, image))
        ..addFile(
          ArchiveFile('word/document.xml', documentXml.length, documentXml),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(bytes.length, greaterThan(1 << 20));
      expect(detectDocumentFormatFromContentSync(bytes), DocumentFormat.docx);
    });
  });
}
