import 'dart:typed_data';

/// קריאות big-endian מבתי SFNT; קריאה מחוץ לתחום מחזירה -1 (ובתג — '').
extension SfntBytes on Uint8List {
  int sfntU16(int o) => (o + 2 > length) ? -1 : (this[o] << 8) | this[o + 1];

  int sfntU32(int o) => (o + 4 > length)
      ? -1
      : (this[o] << 24) |
            (this[o + 1] << 16) |
            (this[o + 2] << 8) |
            this[o + 3];

  String sfntTag(int o) =>
      (o + 4 > length) ? '' : String.fromCharCodes(sublist(o, o + 4));
}
