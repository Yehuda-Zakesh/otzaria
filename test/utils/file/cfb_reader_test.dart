import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/cfb_reader.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';

import 'cfb_fixtures.dart';

Uint8List _bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _filler(int length) =>
    Uint8List.fromList(List.generate(length, (i) => 0x41 + (i % 26)));

void main() {
  group('פענוח מכולה תקינה', () {
    test('זרם קטן נקרא דרך ה-miniFAT', () {
      final bytes = CfbBuilder({
        'WordDocument': _bytesOf('שלום עולם'),
      }).build();

      final cfb = CfbFile.parse(bytes);

      expect(cfb.hasStream('WordDocument'), isTrue);
      expect(utf8.decode(cfb.readStream('WordDocument')!), 'שלום עולם');
    });

    test('זרם גדול נקרא דרך ה-FAT', () {
      final payload = _filler(10000);
      final bytes = CfbBuilder({'WordDocument': payload}).build();

      final cfb = CfbFile.parse(bytes);

      expect(cfb.readStream('WordDocument'), payload);
    });

    test('גודל הזרם מדויק ואינו כולל ריפוד סקטור', () {
      final payload = _filler(700); // חוצה גבול mini-sector
      final bytes = CfbBuilder({'Data': payload}).build();

      expect(CfbFile.parse(bytes).readStream('Data')!.length, 700);
    });

    test('כמה זרמים באותה מכולה', () {
      final bytes = CfbBuilder({
        'WordDocument': _bytesOf('ראשי'),
        '1Table': _bytesOf('טבלה'),
        'SummaryInformation': _filler(6000),
      }).build();

      final cfb = CfbFile.parse(bytes);

      expect(
        cfb.streamNames,
        containsAll(['WordDocument', '1Table', 'SummaryInformation']),
      );
      expect(utf8.decode(cfb.readStream('WordDocument')!), 'ראשי');
      expect(utf8.decode(cfb.readStream('1Table')!), 'טבלה');
      expect(cfb.readStream('SummaryInformation')!.length, 6000);
    });

    test('חיפוש שם אינו תלוי ברישיות', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();
      final cfb = CfbFile.parse(bytes);

      expect(cfb.hasStream('worddocument'), isTrue);
      expect(cfb.hasStream('WORDDOCUMENT'), isTrue);
    });

    test('זרם שאינו קיים מחזיר null', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();

      expect(CfbFile.parse(bytes).readStream('0Table'), isNull);
      expect(CfbFile.parse(bytes).hasStream('0Table'), isFalse);
    });

    test('זרם ריק מוחזר כמערך ריק ולא כ-null', () {
      final bytes = CfbBuilder({'Empty': Uint8List(0)}).build();

      expect(CfbFile.parse(bytes).readStream('Empty'), isEmpty);
    });

    test('רשומת השורש אינה מופיעה כזרם', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();

      expect(CfbFile.parse(bytes).streamNames, isNot(contains('Root Entry')));
    });
  });

  // רגרסיה שנמצאה מול מסמכי Word אמיתיים: מסמך עם אובייקט OLE מוטמע מכיל
  // `WordDocument` ו-`1Table` *פעמיים* — פעם ברמת השורש ופעם בתוך ה-storage
  // של האובייקט. סריקה שטוחה זיווגה זרם ראשי עם טבלה של האובייקט המוטמע,
  // וההמרה נכשלה ב-"CLX חורג מזרם הטבלה".
  group('אובייקט OLE מוטמע', () {
    Uint8List withEmbedded() => CfbBuilder(
      {
        'WordDocument': _bytesOf('המסמך הראשי'),
        '1Table': _bytesOf('טבלת המסמך הראשי'),
      },
      embedded: {
        'WordDocument': _bytesOf('אובייקט מוטמע'),
        '1Table': _bytesOf('טבלת האובייקט המוטמע'),
      },
    ).build();

    test('רק זרמי רמת השורש נראים', () {
      final cfb = CfbFile.parse(withEmbedded());

      expect(cfb.streamNames, ['WordDocument', '1Table']);
      expect(cfb.streamNames.where((n) => n == 'WordDocument').length, 1);
    });

    test('נקרא הזרם הראשי ולא זה של האובייקט המוטמע', () {
      final cfb = CfbFile.parse(withEmbedded());

      expect(utf8.decode(cfb.readStream('WordDocument')!), 'המסמך הראשי');
      expect(utf8.decode(cfb.readStream('1Table')!), 'טבלת המסמך הראשי');
    });

    test('ה-storage עצמו אינו זרם', () {
      expect(CfbFile.parse(withEmbedded()).hasStream('ObjectPool'), isFalse);
    });

    test('המכולה עדיין מזוהה כמסמך Word', () {
      expect(isLegacyWordContainer(withEmbedded()), isTrue);
    });
  });

  group('זיהוי חתימה', () {
    test('hasSignature מזהה CFB', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();
      expect(CfbFile.hasSignature(bytes), isTrue);
    });

    test('hasSignature דוחה קלט אחר', () {
      expect(CfbFile.hasSignature(_bytesOf('סתם טקסט')), isFalse);
      expect(CfbFile.hasSignature(Uint8List(0)), isFalse);
      expect(CfbFile.hasSignature(Uint8List.fromList([0xD0, 0xCF])), isFalse);
    });
  });

  group('מכולה פגומה', () {
    test('חתימה שגויה זורקת', () {
      expect(
        () => CfbFile.parse(_bytesOf('לא CFB')),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('קובץ קצר מ-header זורק', () {
      final short = Uint8List(64)..setRange(0, 8, CfbFile.signature);
      expect(
        () => CfbFile.parse(short),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('גודל סקטור לא נתמך זורק', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();
      ByteData.sublistView(bytes).setUint16(0x1E, 7, Endian.little);

      expect(
        () => CfbFile.parse(bytes),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('סדר בתים שגוי זורק', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();
      ByteData.sublistView(bytes).setUint16(0x1C, 0xFEFF, Endian.little);

      expect(
        () => CfbFile.parse(bytes),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('שרשרת סקטורים מעגלית נעצרת ואינה תוקעת', () {
      final bytes = CfbBuilder({'Data': _filler(10000)}).build();
      // סקטור הספריות מצביע על עצמו — לולאה אינסופית בלי הגנה.
      final fatBase = 512; // סקטור 0
      ByteData.sublistView(bytes).setUint32(fatBase + 4, 1, Endian.little);

      expect(
        () => CfbFile.parse(bytes),
        throwsA(isA<CorruptedDocumentException>()),
      );
    });

    test('החריגה נושאת פורמט ונתיב', () {
      try {
        CfbFile.parse(_bytesOf('לא CFB'), path: 'C:/ספרים/ישן.doc');
        fail('הייתה אמורה להיזרק חריגה');
      } on CorruptedDocumentException catch (e) {
        expect(e.path, 'C:/ספרים/ישן.doc');
      }
    });
  });

  group('isLegacyWordContainer', () {
    test('מכולה עם WordDocument מזוהה', () {
      final bytes = CfbBuilder({
        'WordDocument': _bytesOf('טקסט'),
        '1Table': _bytesOf('טבלה'),
      }).build();

      expect(isLegacyWordContainer(bytes), isTrue);
    });

    test('מכולת OLE שאינה Word אינה מזוהה', () {
      // הבחנה שחתימת ה-OLE לבדה אינה יכולה לעשות: .xls נושא אותה חתימה.
      final bytes = CfbBuilder({'Workbook': _bytesOf('גיליון')}).build();

      expect(CfbFile.hasSignature(bytes), isTrue);
      expect(isLegacyWordContainer(bytes), isFalse);
    });

    test('קלט שאינו CFB אינו מזוהה ואינו זורק', () {
      expect(isLegacyWordContainer(_bytesOf('סתם טקסט')), isFalse);
    });

    test('מכולה פגומה אינה מזוהה ואינה זורקת', () {
      final bytes = CfbBuilder({'WordDocument': _bytesOf('x')}).build();
      ByteData.sublistView(bytes).setUint16(0x1E, 7, Endian.little);

      expect(isLegacyWordContainer(bytes), isFalse);
    });
  });

  // שתי רמות הזיהוי משלימות זו את זו: הראשונה זולה ומספיקה לניתוב למנוע,
  // השנייה יקרה ומכריעה אם מדובר במסמך Word אמיתי.
  group('שילוב עם זיהוי הפורמט', () {
    test('חתימת OLE מנתבת למשפחת Word הישנה', () {
      final word = CfbBuilder({'WordDocument': _bytesOf('טקסט')}).build();
      expect(detectDocumentFormatFromContentSync(word), DocumentFormat.doc);
      expect(isLegacyWordContainer(word), isTrue);
    });

    test('גיליון OLE מקבל אותו זיהוי גס — ונדחה ברמת המכולה', () {
      final sheet = CfbBuilder({'Workbook': _bytesOf('גיליון')}).build();
      expect(detectDocumentFormatFromContentSync(sheet), DocumentFormat.doc);
      expect(
        isLegacyWordContainer(sheet),
        isFalse,
        reason: 'רק פענוח המכולה מבחין בין Word לגיליון',
      );
    });

    test('WBK שתוכנו Word בינארי מנותב למנוע הישן', () {
      final backup = CfbBuilder({'WordDocument': _bytesOf('גיבוי')}).build();
      expect(
        resolveDocumentFormat(DocumentFormat.wbk, backup),
        DocumentFormat.doc,
      );
      expect(isLegacyWordContainer(backup), isTrue);
    });
  });
}
