/// רישום הטקסט של הגליפים לשכבת ההעתקה: מילה שכל הגליפים שלה כבר נרשמו
/// אינה מפורקת שוב לאשכולות, ומפת ToUnicode יוצאת זהה.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:pdf/pdf.dart';

const String _fontPath = 'fonts/TaameyDavidCLM-Medium.ttf';

void main() {
  late Uint8List bytes;
  late ShaperFont shaper;

  setUp(() {
    bytes = File(_fontPath).readAsBytesSync();
    shaper = ShaperFont.register(bytes);
  });

  tearDown(() => shaper.dispose());

  /// מצייר את המילים ומחזיר את מפת ה-ToUnicode ואת מספר האשכולות שפורקו.
  Future<(String, int)> render(List<String> words) async {
    var extracted = 0;
    final document = PdfDocument(compress: false);
    final font = PdfShapedFont(
      document,
      shaper: shaper,
      fontBytes: bytes,
      textForExtraction: (text) {
        extracted++;
        return text;
      },
    );
    final canvas = PdfPage(
      document,
      pageFormat: PdfPageFormat.a4,
    ).getGraphics();
    for (final word in words) {
      font.drawShapedRun(
        canvas,
        shaper.shape(word, rtl: true, script: 'hebr'),
        x: 40,
        y: 400,
        fontSize: 16,
      );
    }
    final text = String.fromCharCodes(await document.save());
    final cmap = text.substring(
      text.indexOf('beginbfchar'),
      text.lastIndexOf('endbfchar'),
    );
    return (cmap, extracted);
  }

  test('מילה שכל הגליפים שלה כבר נרשמו אינה מפורקת שוב', () async {
    final (_, first) = await render(['שָׁלוֹם']);
    final (_, again) = await render(['שָׁלוֹם', 'לוֹם', 'שָׁ']);

    expect(again, first);
  });

  test('מפת ToUnicode זהה כשמילים חוזרות על גליפים שכבר נרשמו', () async {
    final (base, _) = await render(['שָׁלוֹם', 'בְּרֵאשִׁית']);
    final (repeated, _) = await render([
      'שָׁלוֹם',
      'בְּרֵאשִׁית',
      'לוֹם',
      'שִׁית',
      'רֵא',
    ]);

    expect(repeated, base);
  });

  test('מילה עם גליף חדש אחד עדיין נרשמת במלואה', () async {
    final (cmap, _) = await render(['בב', 'בג']);

    expect(cmap, contains('<05D1>'));
    expect(cmap, contains('<05D2>'));
  });
}
