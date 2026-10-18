import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/safer_printer_filter.dart';
import 'package:otzaria/printing/windows_printer_ports.dart';
import 'package:otzaria/printing/windows_printing_platform.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

/// שולח PDF להדפסה. מחוץ למצב סייפר — דיאלוג ההדפסה של המערכת, כרגיל.
/// במצב סייפר הדיאלוג הזה מוביל לסייר הקבצים (Print to PDF, "הדפס לקובץ",
/// "הוסף מדפסת"), ולכן הבחירה נעשית בתוך התוכנה, מתוך מדפסות הנייר בלבד,
/// וההדפסה ישירה. דיאלוג המערכת נפתח בסייפר רק אחרי סיסמה.
///
/// מחזיר האם ההדפסה נשלחה. [context] — לבדיקת מצב הסייפר ולדיאלוגים;
/// כשלא סופק משתמשים בחלון הראשי.
Future<bool> printPdfWithSaferMode({
  required LayoutCallback onLayout,
  required String name,
  PdfPageFormat format = PdfPageFormat.standard,
  bool dynamicLayout = true,
  bool usePrinterSettings = false,
  BuildContext? context,
}) async {
  WindowsPrintingPlatform.install();
  final effectiveContext = context ?? navigatorKey.currentContext;
  if (effectiveContext == null ||
      !shouldRequireSaferModePassword(effectiveContext)) {
    return Printing.layoutPdf(
      onLayout: onLayout,
      name: name,
      format: format,
      dynamicLayout: dynamicLayout,
      usePrinterSettings: usePrinterSettings,
    );
  }

  final printers = SaferPrinterFilter.allowed(
    await Printing.listPrinters(),
    await Isolate.run(windowsPrinterPorts),
  );
  if (!effectiveContext.mounted) return false;

  if (printers.isEmpty) {
    final useSystemDialog = await showTwoActionsDialog(
      context: effectiveContext,
      title: 'אין מדפסת זמינה',
      content: PdfMessages.saferModeNoPrinter,
      confirmText: 'הזן סיסמה',
    );
    if (useSystemDialog != true || !effectiveContext.mounted) return false;
    if (!await verifySaferModePassword(effectiveContext)) return false;
    return Printing.layoutPdf(
      onLayout: onLayout,
      name: name,
      format: format,
      dynamicLayout: dynamicLayout,
      usePrinterSettings: usePrinterSettings,
    );
  }

  final Printer? printer;
  if (printers.length == 1) {
    printer = printers.single;
  } else {
    printer = await showSelectionDialog<Printer>(
      context: effectiveContext,
      title: 'בחירת מדפסת',
      items: [
        for (final p in printers) SelectionItem(label: p.name, value: p),
      ],
      initialValue: printers.where((p) => p.isDefault).firstOrNull,
      searchHint: 'חיפוש מדפסת...',
    );
  }
  if (printer == null) return false;

  final printed = await Printing.directPrintPdf(
    printer: printer,
    onLayout: onLayout,
    name: name,
    format: format,
    dynamicLayout: dynamicLayout,
    usePrinterSettings: usePrinterSettings,
  );
  if (!printed) UiSnack.showError(PdfMessages.printFailed(printer.name));
  return printed;
}
