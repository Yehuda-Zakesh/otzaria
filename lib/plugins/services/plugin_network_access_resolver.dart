import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';

/// בודק האם URL מותר לגישת רשת של תוסף לפי שכבות האמון של אוצריא.
///
/// URL מאושר רק אם:
/// 1. הוא הוצהר ב-`network.allowlist` של התוסף עצמו.
/// 2. הוא מופיע בקובץ `plugin_network_allowlist.txt`: הגרסה החיה בשורש ענף
///    `dev` בריפו אוצריא ב-GitHub, או — כשאין רשת — העותק המקומפל שמחולל
///    מאותו קובץ בזמן הבנייה. עריכת הקובץ נכנסת לתוקף מיד אצל כל
///    המשתמשים, בלי release (ראו תיעוד ב-plugin_network_allowlist.dart).
///
/// אישורים שהגיעו מהקובץ הרשמי ב-GitHub נשמרים **בזיכרון בלבד** עד סגירת
/// האפליקציה; לא נכתבת שום קובץ cache לדיסק.
class PluginNetworkAccessResolver {
  PluginNetworkAccessResolver({
    this._client,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  static PluginNetworkAccessResolver instance = PluginNetworkAccessResolver();

  static const String _officialOwner = 'Otzaria';
  static const String _officialRepository = 'otzaria';
  static const String _officialBranch = 'dev';
  static const String _officialAllowlistFile = 'plugin_network_allowlist.txt';
  static const Duration _officialFetchTimeout = Duration(seconds: 15);
  static const Duration _officialFailureCacheTtl = Duration(minutes: 5);
  static const Set<String> _officialAllowlistContentTypes = <String>{
    'text/plain',
    'application/vnd.github.raw',
  };

  final http.Client? _client;
  final DateTime Function() _nowProvider;
  Future<List<String>?>? _pendingOfficialAllowlistFetch;
  List<String>? _officialAllowlistCache;
  DateTime? _officialAllowlistFailureUntil;

  /// URL ה-raw של קובץ ה-allowlist הרשמי בענף dev בריפו אוצריא.
  static Uri get officialAllowlistUri => Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    pathSegments: <String>[
      _officialOwner,
      _officialRepository,
      _officialBranch,
      _officialAllowlistFile,
    ],
  );

  /// גיבוי ל-[officialAllowlistUri]: אותו קובץ דרך Contents API של GitHub.
  ///
  /// raw.githubusercontent.com נחסם אצל חלק מהמשתמשים ע"י מסנני תוכן (למשל
  /// NetFree) גם כשהם מאושרים לגלוש ל-github.com/api.github.com עצמם — אז
  /// הם נופלים לרשימה המקומפלת מה-build שלהם, שיכולה להיות ישנה ולא לכלול
  /// אישורים חדשים. Contents API אינו נחסם באותו אופן ומגיש את אותו תוכן.
  static Uri get officialAllowlistContentsApiUri => Uri.https(
    'api.github.com',
    '/repos/$_officialOwner/$_officialRepository/contents/'
        '$_officialAllowlistFile',
    <String, String>{'ref': _officialBranch},
  );

  /// מאשר URL לתוסף אם הוא גם הוצהר במניפסט וגם אושר ע"י מקור אמון רשמי.
  Future<bool> isUriAllowedForPlugin(Uri uri, PluginManifest manifest) async {
    // שירותי AI מקומיים: כתובת loopback מותרת אם היא תואמת הצהרת loopback
    // במניפסט (לפי prefix — פורט/נתיב מפורשים נשמרים), בלי לדרוש את
    // ה-allowlist הגלובלי (שאינו נועד ל-localhost).
    if (matchingLoopbackPrefix(uri, manifest.networkAllowlist) != null) {
      return true;
    }

    if (matchingNetworkAllowlistPrefix(uri, manifest.networkAllowlist) ==
        null) {
      return false;
    }

    final officialAllowlist = await _loadOfficialAllowlist();
    if (officialAllowlist != null) {
      // הקובץ בענף הייעודי הוא מקור האמת כשהוא זמין. חשוב לא לבדוק קודם את
      // העותק המקומפל: אחרת אי-אפשר לבטל במהירות כתובת שנפרצה או הוסרה.
      return matchingNetworkAllowlistPrefix(uri, officialAllowlist) != null;
    }

    // גיבוי לא-מקוון בלבד — אותו קובץ כפי שקומפל בזמן הבנייה. שומר על
    // תוספים קיימים כש-GitHub אינו זמין, אך אינו גובר על הרשימה החיה.
    return isUriAllowedForPluginNetwork(uri);
  }

  /// הרשימה הרשמית החיה אם כבר נטענה בהצלחה, בלי להמתין לרשת.
  List<String>? get cachedOfficialAllowlist => _officialAllowlistCache;

  /// טוען את הרשימה הרשמית החיה (או מחזיר אותה מהזיכרון); `null` בכשל.
  Future<List<String>?> loadOfficialAllowlist() => _loadOfficialAllowlist();

  Future<List<String>?> _loadOfficialAllowlist() async {
    final cached = _officialAllowlistCache;
    if (cached != null) return cached;

    final failureUntil = _officialAllowlistFailureUntil;
    if (failureUntil != null && _nowProvider().isBefore(failureUntil)) {
      return null;
    }

    final pending = _pendingOfficialAllowlistFetch;
    if (pending != null) return pending;

    final fetch = _fetchOfficialAllowlist();
    _pendingOfficialAllowlistFetch = fetch;
    try {
      final result = await fetch;
      if (result != null) {
        _officialAllowlistCache = result;
        _officialAllowlistFailureUntil = null;
        // שערי המנוע נבנו עד עכשיו מהעותק המקומפל.
        PluginNetworkPolicy.notifyChanged();
      } else {
        _officialAllowlistFailureUntil = _nowProvider().add(
          _officialFailureCacheTtl,
        );
      }
      return result;
    } finally {
      _pendingOfficialAllowlistFetch = null;
    }
  }

  Future<List<String>?> _fetchOfficialAllowlist() async {
    final client = _client ?? http.Client();
    try {
      final fromRaw = await _tryFetch(client, officialAllowlistUri);
      if (fromRaw != null) return fromRaw;

      // גיבוי ל-raw.githubusercontent החסום.
      return await _tryFetch(
        client,
        officialAllowlistContentsApiUri,
        headers: const <String, String>{
          'Accept': 'application/vnd.github.raw',
        },
      );
    } finally {
      if (_client == null) {
        client.close();
      }
    }
  }

  Future<List<String>?> _tryFetch(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await client
          .get(uri, headers: headers)
          .timeout(_officialFetchTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final contentType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (!_officialAllowlistContentTypes.contains(contentType)) {
        return null;
      }

      final allowlist = parsePluginNetworkAllowlistText(response.body);
      // רשימה ריקה תקפה לחסימת-חירום; תגובת חסימה טקסטואלית אינה רשימה.
      if (allowlist.any((entry) {
        final entryUri = Uri.tryParse(entry);
        return entryUri == null ||
            !entryUri.hasScheme ||
            entryUri.host.isEmpty ||
            (entryUri.scheme != 'http' && entryUri.scheme != 'https');
      })) {
        return null;
      }
      return allowlist;
    } catch (_) {
      return null;
    }
  }
}
