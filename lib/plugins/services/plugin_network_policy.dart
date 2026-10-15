import 'dart:async';

import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';

/// היעדים שתוסף רשאי לפנות אליהם, כרשימה מחושבת מראש.
///
/// זו אותה הכרעה של `evaluatePluginNetworkAccess`, עבור שערים שנאכפים במנוע
/// הדפדפן עצמו (CSP, חוקי החסימה של WebKit) ולכן אינם יכולים לשאול את Dart
/// על כל בקשה.
class PluginNetworkPolicy {
  /// קידומות URL מלאות (http/https), לפי כללי [matchingNetworkAllowlistPrefix].
  final List<String> prefixes;

  /// hosts של loopback שהוצהרו בלי פורט: כל פורט ונתיב עליהם מותרים.
  final List<String> loopbackHosts;

  const PluginNetworkPolicy({
    this.prefixes = const [],
    this.loopbackHosts = const [],
  });

  static const PluginNetworkPolicy none = PluginNetworkPolicy();

  static final StreamController<String?> _changes =
      StreamController<String?>.broadcast();

  /// מזהה התוסף שהמדיניות שלו השתנתה, או `null` כשהשתנתה לכל התוספים.
  static Stream<String?> get changes => _changes.stream;

  static void notifyChanged([String? pluginId]) => _changes.add(pluginId);
}

/// מחשבת את [PluginNetworkPolicy] של התוסף.
///
/// אינה ממתינה לרשימה הרשמית מהרשת: עד שהיא נטענת משמש העותק המקומפל (כמו
/// בשער של Dart כשאין רשת), ובסיום הטעינה נשלחת הודעה ב-[PluginNetworkPolicy.changes].
Future<PluginNetworkPolicy> resolvePluginNetworkPolicy({
  required String pluginId,
  required PluginManifest manifest,
  required PluginRegistryRepository registry,
  PluginNetworkAccessResolver? resolver,
}) async {
  if (!manifest.networkEnabled) return PluginNetworkPolicy.none;
  final remoteGranted =
      await registry.getPermission(pluginId, 'network.access') == true;
  final loopbackGranted =
      await registry.getPermission(pluginId, 'network.localhost') == true;

  final officialResolver = resolver ?? PluginNetworkAccessResolver.instance;
  final cachedOfficial = officialResolver.cachedOfficialAllowlist;
  if (cachedOfficial == null && remoteGranted) {
    unawaited(officialResolver.loadOfficialAllowlist());
  }
  final official = cachedOfficial ?? pluginNetworkAllowlist;

  final prefixes = <String>{};
  final loopbackHosts = <String>{};
  for (final raw in manifest.networkAllowlist) {
    final entry = raw.trim();
    if (entry.isEmpty) continue;
    if (isLoopbackHost(entry)) {
      if (loopbackGranted) loopbackHosts.add(entry.toLowerCase());
      continue;
    }
    final uri = Uri.tryParse(entry);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      continue;
    }
    if (isLoopbackHost(uri.host)) {
      if (loopbackGranted) prefixes.add(entry);
      continue;
    }
    if (!remoteGranted) continue;
    // מותר רק מה שמכוסה גם במניפסט וגם ברשימה הרשמית — הקידומת הצרה מבין השתיים.
    for (final rawOfficial in official) {
      final officialEntry = rawOfficial.trim();
      if (matchingNetworkAllowlistPrefix(uri, [officialEntry]) != null) {
        prefixes.add(entry);
        continue;
      }
      final officialUri = Uri.tryParse(officialEntry);
      if (officialUri != null &&
          matchingNetworkAllowlistPrefix(officialUri, [entry]) != null) {
        prefixes.add(officialEntry);
      }
    }
  }

  return PluginNetworkPolicy(
    prefixes: prefixes.toList(growable: false),
    loopbackHosts: loopbackHosts.toList(growable: false),
  );
}
