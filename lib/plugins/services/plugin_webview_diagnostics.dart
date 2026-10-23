import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// רושם באבחון את מונה תהליכי ה-WebView2 של התוספים. זול ואידמפוטנטי;
/// הסביבה נקראת רק בזמן הדגימה, כשהאבחון פועל.
void registerPluginWebViewDiagnostics() {
  DeveloperDiagnostics.instance.webViewProcessLister ??= _listProcesses;
}

Future<List<WebViewProcess>> _listProcesses() async {
  final environment = WebViewEnvironmentHolder.environment;
  if (environment == null) return const [];
  return pluginWebViewProcesses(await environment.getProcessInfos());
}

/// תהליכי ה-WebView מ-`getProcessInfos()`.
@visibleForTesting
List<WebViewProcess> pluginWebViewProcesses(List<BrowserProcessInfo> infos) => [
  for (final info in infos)
    if (info.processId case final id?)
      (
        kind: info.kind.name(),
        pid: id,
        page: framePageLabel(info.frameInfos?.firstOrNull?.request?.url),
      ),
];

/// התווית של ה-main frame: תיקיית הקובץ (תיקיית התוסף) ב-`file:`, ה-host בשאר.
/// בלי נתיב מלא — הוא חושף את שם המשתמש ביומן.
@visibleForTesting
String? framePageLabel(Uri? url) {
  if (url == null) return null;
  if (url.scheme == 'file') {
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    return segments.length == 1
        ? segments.single
        : '${segments[segments.length - 2]}/${segments.last}';
  }
  return url.host.isEmpty ? null : url.host;
}
