// חילוץ תמונות מוטמעות ממסמך Word בינארי — עץ רשומות ה-OfficeArt שבזרם
// `Data`.
//
// הרגרסיה שהבדיקות מונעות: כל היסט כאן מחושב ידנית (כותר PICF, כותר רשומה,
// דילוג על ה-UID של ה-blip), וטעות של בית אחד מייצרת תמונה משובשת או
// מחיקה שקטה של כל התמונות במסמך.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/file/legacy_word_pictures.dart';

/// סוגי רשומות OfficeArt שהבדיקות משתמשות בהם.
const int _fbse = 0xF007;
const int _blipEmf = 0xF01A;
const int _blipDib = 0xF01F;
const int _blipJpeg = 0xF01D;
const int _blipPng = 0xF01E;

/// `recVer=0xF` מסמן מכולה, שילדיה מתחילים מיד אחרי הכותר.
const int _containerVersion = 0x000F;

/// רשומת OfficeArt: כותר בן 8 בתים ואחריו הגוף.
List<int> _record(int versionAndInstance, int type, List<int> body) => [
  versionAndInstance & 0xFF,
  (versionAndInstance >> 8) & 0xFF,
  type & 0xFF,
  (type >> 8) & 0xFF,
  body.length & 0xFF,
  (body.length >> 8) & 0xFF,
  (body.length >> 16) & 0xFF,
  (body.length >> 24) & 0xFF,
  ...body,
];

/// גוף רשומת blip: rgbUid בן 16 בתים (ועוד אחד כש-instance אי-זוגי), בית
/// `tag`, ואז בייטי התמונה.
List<int> _blipBody(List<int> pixels, {bool twoUids = false}) => [
  ...List.filled(twoUids ? 32 : 16, 0xAA),
  0xFF,
  ...pixels,
];

List<int> _blip(int type, List<int> pixels, {int instance = 0x6E0}) => _record(
  (instance << 4) | 0x00,
  type,
  _blipBody(pixels, twoUids: instance.isOdd),
);

/// עוטף רשומות בעץ `OfficeArtSpContainer` טיפוסי.
List<int> _container(List<int> children) =>
    _record(_containerVersion, 0xF004, children);

/// בונה זרם `Data` עם PICF בהיסט 0 שגופו [records].
///
/// [headerSize] הוא `cbHeader` — האורך שאחריו מתחיל עץ ה-OfficeArt.
Uint8List _dataStream(List<int> records, {int headerSize = 68}) {
  final total = headerSize + records.length;
  final header = List<int>.filled(headerSize, 0);
  header[0] = total & 0xFF;
  header[1] = (total >> 8) & 0xFF;
  header[2] = (total >> 16) & 0xFF;
  header[3] = (total >> 24) & 0xFF;
  header[4] = headerSize & 0xFF;
  header[5] = (headerSize >> 8) & 0xFF;
  return Uint8List.fromList([...header, ...records]);
}

String? _tag(Uint8List data, {bool embedImages = true, int offset = 0}) =>
    legacyWordPictureTag(data, offset, embedImages: embedImages);

void main() {
  final pixels = List<int>.generate(9, (i) => i * 7);
  final expectedBase64 = base64Encode(pixels);

  group('חילוץ blip', () {
    test('PNG בתוך מכולה מוטמע כ-data URI', () {
      final data = _dataStream(_container(_blip(_blipPng, pixels)));

      expect(
        _tag(data),
        '<img src="data:image/png;base64,$expectedBase64" '
        'style="max-width: 100%;"/>',
      );
    });

    test('JPEG מזוהה בטיפוס ה-MIME שלו', () {
      final data = _dataStream(_container(_blip(_blipJpeg, pixels)));

      expect(_tag(data), contains('data:image/jpeg;base64,$expectedBase64'));
    });

    test('blip ישירות תחת ה-PICF, בלי מכולה', () {
      final data = _dataStream(_blip(_blipPng, pixels));

      expect(_tag(data), contains('base64,$expectedBase64'));
    });

    test('instance אי-זוגי — נדחים שני UID ולא אחד', () {
      // rgbUid כפול הוא מה שמבדיל בין 0x6E0 ל-0x6E1. דילוג על אחד בלבד
      // היה מכניס 16 בתים של UID לתוך בייטי התמונה.
      final data = _dataStream(
        _container(_blip(_blipPng, pixels, instance: 0x6E1)),
      );

      expect(_tag(data), contains('base64,$expectedBase64'));
    });

    test('blip בתוך FBSE נמצא אחרי הכותר והשם באורך המשתנה', () {
      // FBSE אינו מכולה (recVer רגיל), ולכן בלי הטיפול המפורש בו לא
      // נמצאת אף תמונה במסמכים שנשמרים כך.
      const nameLength = 4;
      final fbseHeader = List<int>.filled(36, 0)..[33] = nameLength;
      final data = _dataStream(
        _record(0x0000, _fbse, [
          ...fbseHeader,
          ...List.filled(nameLength, 0x20),
          ..._blip(_blipPng, pixels),
        ]),
      );

      expect(_tag(data), contains('base64,$expectedBase64'));
    });

    test('הרשומה הראשונה נבחרת כשיש כמה', () {
      final data = _dataStream(
        _container([
          ..._blip(_blipPng, pixels),
          ..._blip(_blipJpeg, [1, 2, 3]),
        ]),
      );

      expect(_tag(data), contains('image/png'));
    });
  });

  group('תג ריק — התמונה קיימת אך אינה ניתנת להצגה', () {
    // התג נשאר במקומו כדי שמבנה השורות — ועמו עוגני ההערות האישיות ואינדקסי
    // תוכן העניינים — לא יזוז בין הווריאנט המלא לחסר-התמונות.
    const emptyTag = '<img src="" style="max-width: 100%;"/>';

    test('embedImages=false משאיר תג ריק', () {
      final data = _dataStream(_container(_blip(_blipPng, pixels)));

      expect(_tag(data, embedImages: false), emptyTag);
    });

    test('EMF וקטורי — אין לו data URI שהקורא מרנדר', () {
      final data = _dataStream(_container(_blip(_blipEmf, pixels)));

      expect(_tag(data), emptyTag);
    });

    test('DIB — לבייטים חסר כותר bitmap', () {
      final data = _dataStream(_container(_blip(_blipDib, pixels)));

      expect(_tag(data), emptyTag);
    });

    test('תמונה מעל התקרה אינה מוטמעת', () {
      final huge = List<int>.filled(EmbeddedMediaLimits.maxImageBytes + 1, 0);
      final data = _dataStream(_container(_blip(_blipPng, huge)));

      expect(_tag(data), emptyTag);
    });

    test('רשומת blip קטועה — עדיין תמונה, ולכן תג ולא השמטה', () {
      // הגוף קצר מה-UID ומבית ה-tag, כלומר אין בו ולו בית תמונה אחד.
      final data = _dataStream(_record(0x6E0 << 4, _blipPng, [1, 2, 3]));

      expect(_tag(data), emptyTag);
    });
  });

  group('קלט פגום — null ולא תג', () {
    test('היסט שלילי או מעבר לסוף הזרם', () {
      final data = _dataStream(_container(_blip(_blipPng, pixels)));

      expect(_tag(data, offset: -1), isNull);
      expect(_tag(data, offset: data.length - 2), isNull);
    });

    test('cbHeader קטן מכותר PICF מינימלי', () {
      final data = _dataStream(_container(_blip(_blipPng, pixels)))
        ..[4] = 2
        ..[5] = 0;

      expect(_tag(data), isNull);
    });

    test('lcb שאינו גדול מהכותר — אין גוף', () {
      final data = _dataStream(_container(_blip(_blipPng, pixels)))
        ..[0] = 68
        ..[1] = 0
        ..[2] = 0
        ..[3] = 0;

      expect(_tag(data), isNull);
    });

    test('רשומה שאורכה חורג מהגוף', () {
      final data = _dataStream(_container(_blip(_blipPng, pixels)));
      // ניפוח אורך רשומת המכולה מעבר לזרם.
      data[68 + 4] = 0xFF;
      data[68 + 5] = 0xFF;

      expect(_tag(data), isNull);
    });

    test('אין רשומת blip כלל', () {
      final data = _dataStream(_record(0x0000, 0xF00B, List.filled(8, 0)));

      expect(_tag(data), isNull);
    });

    test('קינון עמוק אינו מקריס את המחסנית', () {
      var records = _blip(_blipPng, pixels);
      for (var i = 0; i < 40; i++) {
        records = _container(records);
      }

      expect(_tag(_dataStream(records)), isNull);
    });
  });
}
