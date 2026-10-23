import 'dart:convert';

const String _titlePlaceholder = '{title}';
final RegExp _bannerLinkTarget = RegExp(r'\[([^\]\n]*)\]\(([^)\n]*)\)');

/// מרחיב `{title}` בטקסט באנר מטבלת `banner` בשם הספר: בתוך יעד קישור
/// `[תווית](יעד)` מקודד, ובשאר הטקסט כלשונו — כמו שהמחולל הרחיב עד כה.
String expandBannerTitle(String text, String title) {
  final encoded = _percentEncodeTitle(title);
  final linked = text.replaceAllMapped(
    _bannerLinkTarget,
    (m) => '[${m[1]}](${m[2]!.replaceAll(_titlePlaceholder, encoded)})',
  );
  return linked.replaceAll(_titlePlaceholder, title);
}

/// כמו `URLEncoder.encode(title, UTF_8)` של Java לטקסט תקין, ורווח = `%20`.
/// surrogate בודד הופך ל-`?` לפני הקידוד (Java עצמה אינה עקבית בו).
String _percentEncodeTitle(String title) {
  final out = StringBuffer();
  final wellFormed = String.fromCharCodes(
    title.runes.map((r) => r >= 0xD800 && r <= 0xDFFF ? 0x3F : r),
  );
  for (final byte in utf8.encode(wellFormed)) {
    if (_isKept(byte)) {
      out.writeCharCode(byte);
    } else if (byte == 0x20) {
      out.write('%20');
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

bool _isKept(int byte) =>
    (byte >= 0x61 && byte <= 0x7A) || // a-z
    (byte >= 0x41 && byte <= 0x5A) || // A-Z
    (byte >= 0x30 && byte <= 0x39) || // 0-9
    byte == 0x2E || // .
    byte == 0x2D || // -
    byte == 0x2A || // *
    byte == 0x5F; // _
