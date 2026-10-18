import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fonts = {
  'KetiaAshkenazi': 'fonts/tikkun_korim/Ashkenazi-Stam.ttf',
  'KetiaSefardi': 'fonts/tikkun_korim/Sefardi-Stam.ttf',
  'KetiaKeter': 'fonts/KeterYG-Medium.ttf',
  'KetiaAshurit': 'package:otzaria_ashurit/OtzariaAshurit-Regular.otf',
  'KetiaAshuritBold': 'package:otzaria_ashurit/OtzariaAshurit-Bold.otf',
  'KetiaAshuritNikud':
      'package:otzaria_ashurit/OtzariaAshuritNikud-Regular.otf',
  'KetiaAshuritNikudBold':
      'package:otzaria_ashurit/OtzariaAshuritNikud-Bold.otf',
};

TextPainter _painter(String family, int code) => TextPainter(
  text: TextSpan(
    text: String.fromCharCode(code),
    style: TextStyle(fontFamily: family, fontSize: 128),
  ),
  textDirection: TextDirection.rtl,
)..layout();

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in _fonts.entries) {
      final uri = Uri.parse(entry.value);
      final bytes = uri.scheme == 'package'
          ? (await rootBundle.load('packages/${uri.path}')).buffer.asUint8List()
          : await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final family in _fonts.keys) {
    test('$family — כל החלופות מצוירות ושומרות על רוחב וי״ו', () async {
      final normal = _painter(family, 0x05D5);
      final signatures = <int>{};
      for (var code = 0xE140; code <= 0xE14A; code++) {
        final painter = _painter(family, code);
        expect(painter.width, closeTo(normal.width, 0.001));
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const ui.Offset(8, 8));
        final picture = recorder.endRecording();
        final image = await picture.toImage(160, 200);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final bytes = data.buffer.asUint8List();
        expect(
          [for (var i = 3; i < bytes.length; i += 4) bytes[i]],
          contains(greaterThan(0)),
          reason: 'U+${code.toRadixString(16)}',
        );
        signatures.add(Object.hashAll(bytes));
        image.dispose();
        picture.dispose();
        painter.dispose();
      }
      expect(signatures, hasLength(11));
      normal.dispose();
    });
  }
}
