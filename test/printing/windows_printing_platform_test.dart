import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/windows_printing_platform.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
// ignore: implementation_imports
import 'package:printing/src/method_channel.dart';

class _Plugin extends PrintingPlatform {
  final calls = <Symbol, List<dynamic>>{};
  final results = <Symbol, Object>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls[invocation.memberName] = invocation.positionalArguments;
    return results[invocation.memberName];
  }
}

class _CustomMethodChannel extends MethodChannelPrinting {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('התקנה אינה דורסת מימוש מותאם, גם כשירש מ-MethodChannelPrinting', () {
    final original = PrintingPlatform.instance;
    addTearDown(() => PrintingPlatform.instance = original);
    for (final plugin in <PrintingPlatform>[
      _Plugin(),
      _CustomMethodChannel(),
    ]) {
      PrintingPlatform.instance = plugin;
      WindowsPrintingPlatform.install();
      expect(PrintingPlatform.instance, same(plugin));
    }
  });

  test('התקנה מחליפה רק את ברירת המחדל ב-Windows ופעם אחת בלבד', () {
    final original = PrintingPlatform.instance;
    addTearDown(() => PrintingPlatform.instance = original);
    final plugin = MethodChannelPrinting();
    PrintingPlatform.instance = plugin;
    WindowsPrintingPlatform.install();
    if (Platform.isWindows) {
      expect(PrintingPlatform.instance, isA<WindowsPrintingPlatform>());
    } else {
      expect(PrintingPlatform.instance, same(plugin));
    }
    final installed = PrintingPlatform.instance;
    WindowsPrintingPlatform.install();
    expect(PrintingPlatform.instance, same(installed));
  });

  test('הדפסה רגילה וישירה מעבירות את כל הפרמטרים ותוצאת הביטול', () async {
    final plugin = _Plugin();
    final platform = WindowsPrintingPlatform(plugin);
    final pending = Completer<bool>();
    plugin.results[#layoutPdf] = pending.future;
    Future<Uint8List> layout(PdfPageFormat _) async =>
        Uint8List.fromList([1, 2, 3]);
    for (final printer in [
      null,
      const Printer(url: 'Microsoft Print to PDF', name: 'הדפסה לקובץ'),
    ]) {
      final result = platform.layoutPdf(
        printer,
        layout,
        'ספר בעברית',
        PdfPageFormat.a5,
        false,
        true,
        OutputType.grayscale,
        true,
        false,
      );
      expect(result, same(pending.future));
      expect(plugin.calls[#layoutPdf], [
        printer,
        layout,
        'ספר בעברית',
        PdfPageFormat.a5,
        false,
        true,
        OutputType.grayscale,
        true,
        false,
      ]);
    }
    pending.complete(false);
    expect(await pending.future, isFalse);
  });

  test(
    'כשל בהדפסה אינו משנה או מוחק יעד קיים או קובץ עם סיומת נוספת',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'otzaria_print_failure',
      );
      addTearDown(() => temp.delete(recursive: true));
      final selected = File('${temp.path}/existing.txt');
      final suffixed = File('${selected.path}.pdf');
      await selected.writeAsString('תוכן קיים');
      await suffixed.writeAsString('מסמך PDF קיים');
      final plugin = _Plugin();
      final pending = Completer<bool>();
      plugin.results[#layoutPdf] = pending.future;
      final result = WindowsPrintingPlatform(plugin).layoutPdf(
        const Printer(url: 'Microsoft Print to PDF'),
        (_) async => Uint8List(0),
        selected.path,
        PdfPageFormat.a4,
        true,
        true,
        OutputType.generic,
        false,
        true,
      );
      final expected = expectLater(result, throwsStateError);
      pending.completeError(StateError('כשל בהכנת ההדפסה'));
      await expected;
      expect(await selected.readAsString(), 'תוכן קיים');
      expect(await suffixed.readAsString(), 'מסמך PDF קיים');
    },
  );

  test('כל שאר ממשקי החבילה מועברים ללא שינוי', () async {
    final plugin = _Plugin();
    final platform = WindowsPrintingPlatform(plugin);
    const bounds = Rect.fromLTWH(10, 20, 30, 40);
    const printer = Printer(url: 'מדפסת רשת');
    const info = PrintingInfo(canPrint: true, canListPrinters: true);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final pages = [1, 3];
    final emails = ['user@example.com'];
    final raster = Stream<PdfRaster>.value(PdfRaster(1, 1, Uint8List(4)));
    final infoResult = Future.value(info);
    final pickResult = Future<Printer?>.value(printer);
    final shareResult = Future.value(false);
    final convertResult = Future.value(bytes);
    plugin.results.addAll({
      #info: infoResult,
      #pickPrinter: pickResult,
      #sharePdf: shareResult,
      #convertHtml: convertResult,
      #raster: raster,
    });
    expect(platform.info(), same(infoResult));
    expect(plugin.calls[#info], isEmpty);
    expect(platform.pickPrinter(bounds), same(pickResult));
    expect(plugin.calls[#pickPrinter], [bounds]);
    expect(
      platform.sharePdf(bytes, 'ספר.pdf', bounds, 'נושא', 'תוכן', emails),
      same(shareResult),
    );
    expect(plugin.calls[#sharePdf], [
      bytes,
      'ספר.pdf',
      bounds,
      'נושא',
      'תוכן',
      emails,
    ]);
    expect(
      platform.convertHtml(
        '<b>ספר</b>',
        'https://example.com/',
        PdfPageFormat.a5,
      ),
      same(convertResult),
    );
    expect(plugin.calls[#convertHtml], [
      '<b>ספר</b>',
      'https://example.com/',
      PdfPageFormat.a5,
    ]);
    expect(platform.raster(bytes, pages, 144), same(raster));
    expect(plugin.calls[#raster], [bytes, pages, 144]);
    await raster.drain<void>();
  });
}
