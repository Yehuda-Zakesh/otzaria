import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_vav_ketia.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

Widget _row(TikkunTradition tradition, TikkunVavKetia form) {
  final settings = TikkunSettings(vavKetia: form);
  return ReaderRow(
    line: TikkunLine(
      words: [
        const LayoutWord(stam: 'בריתי', nikud: 'בְּרִיתִי'),
        LayoutWord(
          stam: 'שלום',
          nikud: 'שָׁלֽוֹם',
          vavKetiaTradition: tradition,
        ),
      ],
      layout: LineLayout.partial,
    ),
    metrics: TikkunRenderMetrics.forWidth(1000, settings, lineWidthEm: 8),
    settings: settings,
    hideStam: false,
    hideNikud: false,
    markers: const SizedBox.shrink(),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in {
      ...kTikkunBundledFontAssets,
      'FrankRuhlCLM': 'fonts/FrankRuehlCLM-Medium.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  testWidgets('כל בחירה מגיעה לטקסט המרונדר בשני הטורים', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final tradition in TikkunTradition.values) {
      for (final form in TikkunVavKetia.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: _row(tradition, form)),
            ),
          ),
        );
        final texts = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((t) => t.text.toPlainText())
            .toSet();
        final code = form.codeFor(tradition);
        final vav = code == null ? 'ו' : String.fromCharCode(code);
        expect(texts, containsAll(['של$vavם', 'שָׁלֽ$vavֹם']));
        expect(texts, contains('בריתי'));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('תצוגה אמיתית של ברירות המחדל והחלפה ידנית', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'FrankRuhlCLM'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: RepaintBoundary(
            key: capture,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'וי״ו קטיעא — הרינדור של תיקון קוראים',
                      style: TextStyle(fontSize: 28),
                    ),
                    for (final example in [
                      (
                        'אשכנז וספרד — לפי המסורת',
                        TikkunTradition.ashkenazSephard,
                        TikkunVavKetia.auto,
                      ),
                      (
                        'תימן — לפי המסורת',
                        TikkunTradition.yemen,
                        TikkunVavKetia.auto,
                      ),
                      (
                        'בחירה ידנית — כעין יו״ד',
                        TikkunTradition.yemen,
                        TikkunVavKetia.yod,
                      ),
                    ]) ...[
                      const SizedBox(height: 28),
                      Text(example.$1, style: const TextStyle(fontSize: 22)),
                      _row(example.$2, example.$3),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final output = Platform.environment['TIKKUN_VAV_PREVIEW'];
    if (output != null) {
      await tester.runAsync(() async {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(output).writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
