import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show Rect;
import 'package:otzaria/printing/windows_print_native.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// ignore: implementation_imports
import 'package:printing/src/interface.dart';
// ignore: implementation_imports
import 'package:printing/src/method_channel.dart';

/// מונה מדפסות ב-Windows מחוץ ל-thread של הממשק; שאר הקריאות מועברות לחבילה.
// TODO: להסיר כש-DavBfr/dart_pdf#1985 ישוחרר עם מניית מדפסות ברקע.
class WindowsPrintingPlatform extends PrintingPlatform {
  WindowsPrintingPlatform(this._plugin);

  final PrintingPlatform _plugin;

  /// מתקין ב-Windows בלבד, בלי לדרוס מימוש מותאם שכבר הותקן.
  static void install() {
    if (!Platform.isWindows) return;
    final current = PrintingPlatform.instance;
    if (current.runtimeType == MethodChannelPrinting) {
      PrintingPlatform.instance = WindowsPrintingPlatform(current);
    }
  }

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) {
    return _plugin.layoutPdf(
      printer,
      onLayout,
      name,
      format,
      dynamicLayout,
      usePrinterSettings,
      outputType,
      forceCustomPrintPaper,
      windowsModernDialog,
    );
  }

  @override
  Future<List<Printer>> listPrinters() => Isolate.run(listWindowsPrinters);

  @override
  Future<PrintingInfo> info() => _plugin.info();

  @override
  Future<Printer?> pickPrinter(Rect bounds) => _plugin.pickPrinter(bounds);

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) => _plugin.sharePdf(bytes, filename, bounds, subject, body, emails);

  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) => _plugin.convertHtml(html, baseUrl, format);

  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      _plugin.raster(document, pages, dpi);
}
