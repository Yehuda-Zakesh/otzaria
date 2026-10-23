import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';

const String pluginContentSecurityPolicyHeader = 'Content-Security-Policy';

/// מדיניות CSP לדפי התוסף: כל טעינה ובקשה מוגבלת לקבצי התוסף, לנתיבים שלו
/// בשרת הקבצים ([fileServerPort]) וליעדים שב-[policy].
///
/// inline ו-eval נשארים מותרים: כאן ה-CSP הוא שער רשת, לא הגנה מפני XSS.
String buildPluginContentSecurityPolicy({
  required String pluginId,
  required PluginNetworkPolicy policy,
  required int fileServerPort,
}) {
  final sources = <String>[
    "'self'",
    '$pluginAssetScheme://${pluginAssetHost(pluginId)}',
    if (!pluginAssetSchemeEnabled) 'file:',
    'data:',
    'blob:',
    for (final host in const ['127.0.0.1', 'localhost']) ...[
      'http://$host:$fileServerPort/f/${Uri.encodeComponent(pluginId)}/',
      'http://$host:$fileServerPort/w/',
      'http://$host:$fileServerPort/fonts/',
    ],
    for (final prefix in policy.prefixes) ..._sourcesForPrefix(prefix),
    for (final host in policy.loopbackHosts)
      for (final scheme in const ['http', 'https', 'ws', 'wss'])
        '$scheme://${_urlHost(host)}:*',
  ];
  final list = sources.join(' ');
  const scripts = "'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'";
  return "default-src $list $scripts; form-action $list; base-uri 'self'";
}

String _urlHost(String host) => host.contains(':') ? '[$host]' : host;

/// מקור CSP אינו יכול לכלול query: נשאר הנתיב, ובלי `/` סופי הוא תואם רק
/// את הנתיב עצמו — לכן מתווסף גם הנתיב עם `/` לכל מה שתחתיו. WebSocket לאותו
/// יעד מותר גם הוא, כמו בחוקי החסימה.
List<String> _sourcesForPrefix(String prefix) {
  final uri = Uri.tryParse(prefix);
  if (uri == null ||
      uri.host.isEmpty ||
      RegExp(r"[\s'\x22]").hasMatch(prefix)) {
    return const [];
  }
  final authority =
      '${uri.host.toLowerCase()}${uri.hasPort ? ':${uri.port}' : ''}';
  final path = uri.path.replaceAll(';', '%3B').replaceAll(',', '%2C');
  final scheme = uri.scheme.toLowerCase();
  return [
    for (final s in [scheme, scheme == 'https' ? 'wss' : 'ws'])
      if (path.isEmpty || path == '/')
        '$s://$authority'
      else ...[
        '$s://$authority$path',
        if (!path.endsWith('/')) '$s://$authority$path/',
      ],
  ];
}

/// הוראת `frame-ancestors` לקובץ שמוגש משרת הקבצים ל-[pluginId]: רק דף של
/// התוסף רשאי להטמיע אותו ב-`<iframe>`. תחליף ל-`X-Frame-Options: SAMEORIGIN`,
/// שחוסם גם את דף התוסף (origin אחר מהשרת).
///
/// דף שמוגש מ-`file://` אינו מקבל origin משלו, ו-CSP אינו יכול להבחין בין
/// נתיבים — לכן בפלטפורמות האלה גם דף `file://` של תוסף אחר עובר את הבדיקה.
/// זה לא פותח את הקובץ: ההטמעה נשארת cross-origin, ו-URL הקובץ כולל token
/// סודי של התוסף.
///
/// [assetSchemeOnly] מחליף את זיהוי הפלטפורמה (`pluginAssetSchemeEnabled`),
/// לבדיקות.
String pluginFrameAncestorsDirective(
  String pluginId, {
  bool? assetSchemeOnly,
}) =>
    'frame-ancestors $pluginAssetScheme://${pluginAssetHost(pluginId)}'
    '${(assetSchemeOnly ?? pluginAssetSchemeEnabled) ? '' : ' file:'}';
