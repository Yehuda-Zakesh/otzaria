import 'dart:async';

import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

/// מעקב שאינו תלוי במחזור החיים של מסך ההדפסה.
abstract final class PrintWorkStatus {
  static int _activeJobs = 0;

  static bool get hasActiveJobs => _activeJobs > 0;

  static Future<bool> track(FutureOr<bool> Function() print) async {
    _activeJobs++;
    try {
      return await print();
    } finally {
      _activeJobs--;
    }
  }
}

/// מאשר סגירה כשהדפסה עדיין נשלחת: סגירת החלון עלולה לקטוע אותה.
Future<bool> confirmCloseWhilePrinting() async {
  if (!PrintWorkStatus.hasActiveJobs) return true;
  final context = navigatorKey.currentContext;
  if (context == null) return true;
  final confirmed = await showConfirmationDialog(
    context: context,
    title: PdfMessages.closeWhilePrintingTitle,
    content: PdfMessages.closeWhilePrinting,
    confirmText: PdfMessages.closeWhilePrintingConfirm,
    isDangerous: true,
  );
  return confirmed == true;
}
