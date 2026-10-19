import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';

/// override לבדיקות בלבד: כתיבה לקובץ גם ב-debug (ברירת המחדל שם היא הדפסה).
@visibleForTesting
bool debugForcePluginWebViewFailureFileLog = false;

/// רישום כשלי שכבת ה-WebView של התוספים ל-errors.txt (best-effort).
///
/// כשלים אלה מסתיימים אצל המשתמש במסך ריק בלי שום עקבות — הרישום כאן הוא
/// הדרך היחידה לאבחן אותם מרחוק. ב-debug מודפס לקונסול בלבד.
/// [creationFailure] מוסיף ברקע אבחון של סביבת WebView2 (Windows בלבד).
void logPluginWebViewFailure(
  String title,
  Object error, {
  StackTrace? stackTrace,
  Map<String, String?> details = const {},
  bool creationFailure = false,
}) {
  if (kDebugMode && !debugForcePluginWebViewFailureFileLog) {
    debugPrint('Plugin WebView failure [$title]: $error');
    return;
  }
  try {
    ErrorLogFile.append(
      title: title,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  } catch (_) {}
  if (creationFailure) WebView2CreationDiagnostics.recordCreationFailure(error);
}
