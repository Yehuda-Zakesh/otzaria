import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';

/// האם רשת התוסף נאכפת בחוקי החסימה של WebKit. בפלטפורמות האלה אין
/// `shouldInterceptRequest` לבקשות http(s), ובלי החוקים fetch ישיר עוקף כל שער.
bool get pluginNetworkUsesContentBlockers =>
    !kIsWeb && (Platform.isMacOS || Platform.isIOS || Platform.isLinux);

/// התווים שמותרים בקידומת שהופכת לחוק. כל תו אחר — הקידומת נפסלת ולא מותרת,
/// כי תחביר הביטויים של WebKit חלקי ותו לא צפוי היה פוסל את כל רשימת החוקים.
final RegExp _ruleSafePrefix = RegExp(
  r"^[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+$",
);

/// תווים בעלי משמעות בביטויי `url-filter` של WebKit.
final RegExp _regexSpecial = RegExp(r'[\\.*+?^$()\[\]{}|]');

String _escape(String literal) =>
    literal.replaceAllMapped(_regexSpecial, (m) => '\\${m[0]}');

/// בונה את חוקי החסימה של WebKit לתוסף: חוסם כל טעינה, ומחריג רק את קבצי
/// התוסף עצמו, את הנתיבים שלו בשרת הקבצים ([fileServerPort]) ואת היעדים
/// שב-[policy].
///
/// [devServerOrigin] — שרת הפיתוח של תוסף שנטען מ-localhost.
List<ContentBlocker> buildPluginContentBlockers({
  required String pluginId,
  required PluginNetworkPolicy policy,
  required int fileServerPort,
  String? devServerOrigin,
}) {
  final allowed = <String>[
    '^about:',
    '^data:',
    '^blob:',
    if (pluginAssetSchemeEnabled)
      '^${_escape('$pluginAssetScheme://${pluginAssetHost(pluginId)}/')}'
    else
      // דף התוסף עצמו נטען מ-file://; הקריאה מוגבלת בנפרד לתיקיית התוסף.
      '^file:',
  ];
  final fileServers = [
    for (final host in const ['127\\.0\\.0\\.1', 'localhost'])
      '^http://$host:$fileServerPort/',
  ];

  void allowPrefix(Uri uri, String rest) {
    final authority =
        '${uri.host.toLowerCase()}${uri.hasPort ? ':${uri.port}' : ''}';
    for (final scheme in _schemesFor(uri.scheme.toLowerCase())) {
      final escaped = _escape('$scheme://$authority$rest');
      allowed
        ..add('^$escaped\$')
        ..add('^$escaped[/?#]');
    }
  }

  if (devServerOrigin != null) {
    final dev = Uri.tryParse(devServerOrigin);
    if (dev != null && dev.host.isNotEmpty) allowPrefix(dev, '');
  }
  for (final prefix in policy.prefixes) {
    if (!_ruleSafePrefix.hasMatch(prefix)) continue;
    final uri = Uri.tryParse(prefix);
    if (uri == null || uri.host.isEmpty) continue;
    allowPrefix(
      uri,
      '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
      '${uri.hasFragment ? '#${uri.fragment}' : ''}',
    );
  }
  for (final host in policy.loopbackHosts) {
    final urlHost = host.contains(':') ? '[$host]' : host;
    allowed
      ..add('^https?://${_escape(urlHost)}[:/]')
      ..add('^wss?://${_escape(urlHost)}[:/]');
  }
  return [
    _block('.*'),
    ...allowed.map(_allow),
    // הצהרת loopback אינה פותחת את שרת הקבצים: מותרים בו רק הנתיבים של התוסף.
    ...fileServers.map(_block),
    for (final server in fileServers) ...[
      _allow('$server${_escape('f/${Uri.encodeComponent(pluginId)}/')}'),
      _allow('${server}w/'),
      _allow('${server}fonts/'),
    ],
  ];
}

ContentBlocker _block(String filter) => ContentBlocker(
  trigger: ContentBlockerTrigger(urlFilter: filter),
  action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
);

ContentBlocker _allow(String filter) => ContentBlocker(
  trigger: ContentBlockerTrigger(
    urlFilter: filter,
    urlFilterIsCaseSensitive: true,
  ),
  action: ContentBlockerAction(
    type: ContentBlockerActionType.IGNORE_PREVIOUS_RULES,
  ),
);

/// WebSocket ליעד מותר עובר באותו host, ולכן מותר גם הוא.
List<String> _schemesFor(String scheme) => switch (scheme) {
  'https' => const ['https', 'wss'],
  'http' => const ['http', 'ws'],
  _ => [scheme],
};
