/// חילוץ תמונות מוטמעות ממסמך Word בינארי.
///
/// התמונה אינה יושבת בזרם הטקסט אלא בזרם `Data`, ו-`sprmCPicLocation` שב-CHPX
/// של תו ה-placeholder (0x01) מצביע אליה. בהיסט הזה יושב `PICF`, ואחריו עץ
/// רשומות OfficeArt שבתוכו ה-blip עם הבייטים עצמם.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';

/// מחזיר את תג ה-`<img>` של התמונה שבהיסט [offset] בזרם [data].
///
/// `null` = אין שם תמונה שניתן לזהות, ואין לפלוט תג. מחרוזת שה-`src` שלה ריק
/// = תמונה בפורמט שאין לו data URI (WMF/EMF וקטוריים) או שחורגת מהתקרה;
/// התג נשמר כדי שמבנה השורות לא יזוז.
String? legacyWordPictureTag(
  Uint8List data,
  int offset, {
  required bool embedImages,
}) {
  // PICF: lcb (4) + cbHeader (2), ואחרי cbHeader מתחיל עץ ה-OfficeArt.
  if (offset < 0 || offset + 6 > data.length) return null;
  final view = ByteData.sublistView(data);
  final total = view.getUint32(offset, Endian.little);
  final headerSize = view.getUint16(offset + 4, Endian.little);
  if (headerSize < 6 || total <= headerSize) return null;

  final start = offset + headerSize;
  final end = offset + total > data.length ? data.length : offset + total;
  if (start >= end) return null;

  final blip = _findBlip(data, start, end);
  if (blip == null) return null;
  if (!embedImages ||
      blip.mime == null ||
      blip.length > EmbeddedMediaLimits.maxImageBytes) {
    return otzariaImage('');
  }

  final bytes = Uint8List.sublistView(
    data,
    blip.start,
    blip.start + blip.length,
  );
  return otzariaImage('data:${blip.mime};base64,${base64Encode(bytes)}');
}

/// בייטי תמונה שנמצאו בעץ ה-OfficeArt.
class _Blip {
  final int start;
  final int length;

  /// `null` לפורמט שאין לו data URI שהקורא מרנדר.
  final String? mime;

  const _Blip(this.start, this.length, this.mime);
}

/// סוגי רשומות ה-blip של OfficeArt, וה-MIME המתאים.
const Map<int, String?> _blipTypes = {
  0xF01A: null, // EMF
  0xF01B: null, // WMF
  0xF01C: null, // PICT
  0xF01D: 'image/jpeg',
  0xF01E: 'image/png',
  0xF01F: null, // DIB — הבייטים חסרים כותר bitmap, ולכן אין להם data URI
  0xF029: null, // TIFF
  0xF02A: 'image/jpeg',
};

/// `OfficeArtFBSE` — רשומת ה-BLIP Store Entry שבתוכה מוטמעת התמונה.
const int _fbseRecord = 0xF007;
const int _fbseHeaderSize = 36;
const int _fbseNameLengthOffset = 33;

/// עומק הקינון המרבי בעץ הרשומות. עץ אמיתי רחוק מכאן, ורקורסיה בלי תקרה על
/// קובץ פגום הייתה מקריסה את המחסנית.
const int _maxRecordDepth = 16;

/// סורק את עץ רשומות ה-OfficeArt ומחזיר את ה-blip הראשון.
///
/// כל רשומה פותחת בכותר בן 8 בתים; `recVer == 0xF` מסמן מכולה, שילדיה
/// מתחילים מיד אחרי הכותר.
_Blip? _findBlip(Uint8List data, int from, int to, [int depth = 0]) {
  if (depth > _maxRecordDepth) return null;
  final view = ByteData.sublistView(data);
  var cursor = from;

  while (cursor + 8 <= to) {
    final versionAndInstance = view.getUint16(cursor, Endian.little);
    final recordType = view.getUint16(cursor + 2, Endian.little);
    final length = view.getUint32(cursor + 4, Endian.little);
    final body = cursor + 8;
    if (body + length > to) return null;

    if ((versionAndInstance & 0x000F) == 0x000F) {
      final found = _findBlip(data, body, body + length, depth + 1);
      if (found != null) return found;
    } else if (recordType == _fbseRecord) {
      // FBSE הוא אטום ולא מכולה, אך ה-blip מוטמע בתוכו אחרי כותר קבוע בן 36
      // בתים ושם באורך משתנה. בלי הירידה לכאן לא נמצאת אף תמונה.
      if (length > _fbseHeaderSize) {
        final nameLength = data[body + _fbseNameLengthOffset];
        final blipStart = body + _fbseHeaderSize + nameLength;
        if (blipStart < body + length) {
          final found = _findBlip(data, blipStart, body + length, depth + 1);
          if (found != null) return found;
        }
      }
    } else if (_blipTypes.containsKey(recordType)) {
      final instance = (versionAndInstance >> 4) & 0x0FFF;
      // rgbUid בן 16 בתים, ועוד אחד כשה-instance אי-זוגי, ואז בית `tag`.
      final skip = 16 + (instance.isOdd ? 16 : 0) + 1;
      if (length > skip) {
        return _Blip(body + skip, length - skip, _blipTypes[recordType]);
      }
      return _Blip(body, 0, null);
    }

    cursor = body + length;
  }
  return null;
}
