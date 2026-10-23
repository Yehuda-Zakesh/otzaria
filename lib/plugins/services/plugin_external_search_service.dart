import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/search/models/search_match_policy.dart';

typedef ExternalSearchEventDispatcher =
    Future<void> Function(
      String pluginId,
      String topic,
      Map<String, dynamic> payload, {
      bool preferBackground,
    });

/// תוצאת ספר יחידה ממקור חיפוש חיצוני של תוסף (למשל היברובוקס).
class ExternalSearchResult {
  final String title;

  /// שורת מטא-נתונים להצגה (מחבר · מקום · שנה).
  final String? meta;

  /// קטע טקסט רגיל מסביב להתאמה; ההדגשה נעשית בצד המסך לפי השאילתה.
  final String? snippet;

  final int hitCount;

  /// עמוד ההתאמה הראשונה, מבוסס-1.
  final int? firstPage;

  final String provider;
  final Object externalId;

  const ExternalSearchResult({
    required this.title,
    this.meta,
    this.snippet,
    required this.hitCount,
    this.firstPage,
    required this.provider,
    required this.externalId,
  });
}

/// רשומת אינדקס: תוצאה אחת בתמצות — מזהה, מופעים, קטגוריית אוצריא
/// המשוערת שהספק גזר מהקטלוג שלו (null כשאין לו סיווג), ושם הספר.
///
/// השם אופציונלי (ספק ותיק אינו שולח אותו): בלעדיו הדלי
/// "עוד מ<מקור>" בעץ הסינון נשאר שורה שאי אפשר לפתוח, כי אין ממה לבנות
/// את שורות הספרים שתחתיו.
class ExternalSearchIndexEntry {
  final int id;
  final int hits;
  final String? categoryPath;
  final String? title;

  const ExternalSearchIndexEntry({
    required this.id,
    required this.hits,
    this.categoryPath,
    this.title,
  });
}

/// עמוד תוצאות ממקור חיצוני.
class ExternalSearchPage {
  final List<ExternalSearchResult> results;
  final int totalBooks;
  final int totalHits;
  final bool hasMore;

  /// אינדקס כלל תוצאות החיפוש (לא רק העמוד) — נשלח על בקשת העמוד הראשון
  /// ומשמש לבניית ספירות הקטגוריות בעץ החיפוש ולדפדוף מסונן. null כשהספק
  /// לא צירף אינדקס לעדכון הזה.
  final List<ExternalSearchIndexEntry>? index;

  const ExternalSearchPage({
    required this.results,
    required this.totalBooks,
    required this.totalHits,
    required this.hasMore,
    this.index,
  });
}

/// ספקי תוצאות חיצוניים למסך החיפוש המובנה.
///
/// אוצריא אינה מדברת עם מנועי חיפוש חיצוניים בעצמה (התקשורת עם שירות
/// HebrewBooks שייכת לתוסף בלבד). תוסף נרשם כספק עבור provider חיצוני,
/// מסך החיפוש שולח אליו בקשה כאירוע ממוקד `search.external.requested`,
/// והתוסף עונה בקריאת bridge `reader.respondExternalSearch` עם עמוד תוצאות.
class PluginExternalSearchService {
  PluginExternalSearchService._()
    : _dispatch = ((pluginId, topic, payload, {preferBackground = false}) =>
          PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
            pluginId,
            topic,
            payload,
            preferBackground: preferBackground,
          ));
  static final PluginExternalSearchService instance =
      PluginExternalSearchService._();

  @visibleForTesting
  PluginExternalSearchService.forTesting(this._dispatch);

  static const requestTopic = 'search.external.requested';

  /// חיפוש מלא מול שירות חיצוני עשוי לקחת זמן; הספק שולח תשובות חלקיות
  /// (`done: false`) תוך כדי, ולכן הטיימאוט הוא חוסר-פעילות — הוא מתאפס
  /// בכל עדכון חלקי במקום למדוד את משך החיפוש כולו.
  static const _inactivityTimeout = Duration(seconds: 45);

  static const _maxResultsPerPage = 50;
  static const _maxTitleLength = 300;
  static const _maxMetaLength = 300;
  static const _maxSnippetLength = 600;
  static const _maxIndexEntries = 20000;
  static const _maxCategoryPathLength = 200;
  static const _maxRequestedIds = 50;

  final Map<String, String> _providerToPlugin = {};
  final Map<String, _PendingExternalSearch> _pending = {};
  final ExternalSearchEventDispatcher _dispatch;
  int _requestCounter = 0;

  /// האם [pluginId] רשום כספק כלשהו.
  bool isProviderPlugin(String pluginId) =>
      _providerToPlugin.containsValue(pluginId);

  /// רושם את [pluginId] כספק הבלעדי של [provider].
  void register(String provider, String pluginId) {
    final owner = _providerToPlugin[provider];
    if (owner != null && owner != pluginId) {
      throw StateError('Provider "$provider" is already owned by "$owner"');
    }
    _providerToPlugin[provider] = pluginId;
    debugPrint('PluginExternalSearchService: $pluginId provides "$provider"');
  }

  bool hasProvider(String provider) => _providerToPlugin.containsKey(provider);

  /// מסיר את כל הספקים של התוסף ומכשיל מיד בקשות פעילות שלו.
  void removePlugin(String pluginId) {
    _providerToPlugin.removeWhere((_, owner) => owner == pluginId);
    for (final entry in _pending.entries.toList()) {
      final pending = entry.value;
      if (pending.pluginId != pluginId) continue;
      _pending.remove(entry.key);
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          StateError('External search provider is no longer available'),
        );
      }
    }
  }

  /// שולח שאילתה מעומדת לספק של [provider] ומחזיר את עמוד התוצאות הסופי.
  /// עדכונים חלקיים תוך כדי החיפוש (`done: false` מהספק) נמסרים ל-[onUpdate]
  /// עם ספירות שהן רף-תחתון. זורק [TimeoutException] כשהתוסף הפסיק לענות,
  /// או [StateError] כשאין ספק.
  Future<ExternalSearchPage> search({
    required String provider,
    required String query,
    String mode = 'exact',
    int distance = 1,
    SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
    int offset = 0,
    int limit = 20,
    List<int>? ids,
    Map<String, bool> options = const {},
    Map<String, Map<String, bool>> wordOptions = const {},
    void Function(ExternalSearchPage partial)? onUpdate,
  }) async {
    final pluginId = _providerToPlugin[provider];
    if (pluginId == null) {
      throw StateError('No external search provider for "$provider"');
    }
    if (ids != null &&
        (ids.isEmpty ||
            ids.length > _maxRequestedIds ||
            ids.any((id) => id <= 0))) {
      throw ArgumentError('ids must hold 1-$_maxRequestedIds positive ids');
    }
    final requestId = 'xs-${++_requestCounter}';
    debugPrint(
      'PluginExternalSearchService: → $requestId "$query" '
      '${ids != null ? 'ids=${ids.length}' : 'offset=$offset limit=$limit'} '
      'provider=$provider',
    );
    final pending = _PendingExternalSearch(
      pluginId: pluginId,
      provider: provider,
      onUpdate: onUpdate,
      inactivityTimeout: _inactivityTimeout,
    );
    _pending[requestId] = pending;
    final eventPayload = {
      'requestId': requestId,
      'provider': provider,
      'query': query,
      'mode': mode,
      'distance': distance,
      // בטווח "פסקה"/"כותרת" או בהתאמה חלקית המרווח חסר משמעות — בלי המדיניות
      // הספק היה מחפש במרווח המחמיר ביותר (issue #1427).
      ...matchPolicy.toJson(),
      'offset': offset,
      'limit': limit,
      // עמוד לפי מזהים מפורשים: דפדוף בתוצאות מסוננות-קטגוריה שהקורא
      // חישב מהאינדקס. הספק מגיש אותם מהמטמון של החיפוש.
      'ids': ?ids,
      // אפשרויות חיפוש בפורמט של search.requested — הספק מחיל את מה שהמנוע
      // שלו תומך בו. options היא המפה הגלובלית (חלה על כל מילות השאילתה) —
      // בלעדיה ספק שמפרק את השאילתה למילים אחרת (מקף, פיסוק) לא היה מזהה
      // את מפתחות ה-wordOptions והאפשרויות היו מתבטלות בשקט.
      'options': ?(options.isEmpty ? null : options),
      'wordOptions': ?(wordOptions.isEmpty ? null : wordOptions),
      // הקורא צורך שמות ספרים באינדקס. ספק ותיק מתעלם מהשדה ושולח רשומות
      // בלי שם; ספק שמכיר אותו יודע שהשם לא ייזרק — ומארח ותיק, שאינו
      // שולח את השדה, לא יקבל רשומות שהיה זורק בסניטציה. רק בקשת העמוד
      // הראשון נושאת אינדקס, ואין טעם להזמין שמות לעמוד שלא יביא אותו.
      'indexTitles': ?(ids == null && offset == 0 ? true : null),
    };
    Timer? retryTimer;
    try {
      // לא ממתינים ל-dispatch לפני ההאזנה לתשובה: מסלול ההעֲרָה (פתיחת דף
      // התוסף) עשוי לקחת זמן, וטיימאאוט שנורה בלי מאזין היה הופך לחריגה
      // לא-מטופלת והמדור היה נתקע בטעינה לנצח.
      final dispatch = _dispatch(
        pluginId,
        requestTopic,
        eventPayload,
        preferBackground: true,
      );
      unawaited(
        dispatch.catchError((Object error, StackTrace stackTrace) {
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(error, stackTrace);
          }
        }),
      );
      // מסירה לתוסף שזה עתה הוּעַר עלולה להתנקז לדף שעוד לא רשם מאזינים
      // (טעינה-מחדש באמצע resume) — האירוע אובד בשקט. אם אין שום תגובה
      // תוך זמן קצר, משגרים שוב פעם אחת; הבקשה אידמפוטנטית (אותו requestId,
      // והחיפוש עצמו נענה מהמטמון של התוסף).
      retryTimer = Timer(const Duration(seconds: 8), () {
        if (pending.completer.isCompleted || pending.sawActivity) return;
        debugPrint(
          'PluginExternalSearchService: retrying $requestId (no response)',
        );
        unawaited(
          _dispatch(
            pluginId,
            requestTopic,
            eventPayload,
            preferBackground: true,
          ).catchError((_) {}),
        );
      });
      return await pending.completer.future;
    } finally {
      retryTimer?.cancel();
      pending.dispose();
      _pending.remove(requestId);
    }
  }

  /// תשובת התוסף לבקשה: רשימת תוצאות גולמית שעוברת ניקוי וקיצוץ כאן.
  /// `done: false` מסמן עדכון חלקי — הבקשה נשארת פתוחה והטיימאוט מתאפס;
  /// תשובה לבקשה שכבר פגה, שאינה שייכת ל-[pluginId] או שהגיעה ממופע אחר
  /// של התוסף ([instanceId]) נדחית.
  bool respond(
    String pluginId,
    String requestId, {
    List<Object?> results = const [],
    int totalBooks = 0,
    int totalHits = 0,
    bool hasMore = false,
    bool done = true,
    List<Object?>? index,
    String? error,
    String? instanceId,
  }) {
    debugPrint(
      'PluginExternalSearchService: ← $requestId done=$done '
      'results=${results.length} totalBooks=$totalBooks '
      'index=${index?.length} error=$error',
    );
    final pending = _pending[requestId];
    if (pending == null ||
        pending.pluginId != pluginId ||
        pending.completer.isCompleted) {
      return false;
    }
    if (!pending.bindResponder(instanceId)) return false;
    pending.sawActivity = true;
    if (error != null && error.isNotEmpty) {
      _pending.remove(requestId);
      pending.completer.completeError(StateError(error));
      return true;
    }
    final sanitized = <ExternalSearchResult>[];
    for (final raw in results.take(_maxResultsPerPage)) {
      final result = _sanitizeResult(raw, pending.provider);
      if (result != null) sanitized.add(result);
    }
    final page = ExternalSearchPage(
      results: sanitized,
      totalBooks: totalBooks < 0 ? 0 : totalBooks,
      totalHits: totalHits < 0 ? 0 : totalHits,
      hasMore: hasMore,
      index: _sanitizeIndex(index),
    );
    if (!done) {
      pending.touch();
      pending.onUpdate?.call(page);
      return true;
    }
    _pending.remove(requestId);
    pending.completer.complete(page);
    return true;
  }

  ExternalSearchResult? _sanitizeResult(Object? raw, String provider) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final externalId = raw['externalId'];
    if (title is! String || title.isEmpty) return null;
    if (externalId is! num && (externalId is! String || externalId.isEmpty)) {
      return null;
    }
    final hitCount = raw['hitCount'];
    final firstPage = raw['firstPage'];
    return ExternalSearchResult(
      title: _clip(title, _maxTitleLength)!,
      meta: _clip(raw['meta'], _maxMetaLength),
      snippet: _clip(raw['snippet'], _maxSnippetLength),
      hitCount: hitCount is num && hitCount > 0 ? hitCount.toInt() : 0,
      firstPage: firstPage is num && firstPage >= 1 ? firstPage.toInt() : null,
      provider: provider,
      externalId: externalId is num ? externalId.toInt() : externalId!,
    );
  }

  @visibleForTesting
  List<ExternalSearchIndexEntry>? sanitizeIndexForTesting(List<Object?>? raw) =>
      _sanitizeIndex(raw);

  /// אינדקס גולמי מהספק: רשימת מערכים [id, hits], [id, hits, category] או
  /// [id, hits, category, title] (קטגוריה ריקה כשיש שם בלי סיווג).
  /// רשומות פגומות נזרקות; נתיב קטגוריה חייב להתחיל ב-'/' (בלי לוודא מול
  /// הספרייה — זו אחריות הקורא, שממילא מאחד נתיבים לא מוכרים לדלי משלו).
  List<ExternalSearchIndexEntry>? _sanitizeIndex(List<Object?>? raw) {
    if (raw == null) return null;
    final entries = <ExternalSearchIndexEntry>[];
    for (final item in raw.take(_maxIndexEntries)) {
      if (item is! List || item.length < 2 || item.length > 4) continue;
      final id = item[0];
      final hits = item[1];
      if (id is! num || id < 1 || hits is! num || hits < 0) continue;
      String? categoryPath;
      if (item.length >= 3) {
        final path = _clip(item[2], _maxCategoryPathLength);
        if (path != null && path.startsWith('/') && path.length > 1) {
          categoryPath = path;
        }
      }
      entries.add(
        ExternalSearchIndexEntry(
          id: id.toInt(),
          hits: hits.toInt(),
          categoryPath: categoryPath,
          title: item.length == 4 ? _clip(item[3], _maxTitleLength) : null,
        ),
      );
    }
    return entries;
  }

  String? _clip(Object? value, int maxLength) {
    if (value is! String) return null;
    final text = value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim();
    if (text.isEmpty) return null;
    return text.length <= maxLength ? text : text.substring(0, maxLength);
  }
}

/// בקשה פתוחה: ה-completer לעמוד הסופי, callback לעדכונים חלקיים, וטיימר
/// חוסר-פעילות שמתאפס בכל עדכון.
class _PendingExternalSearch {
  final String pluginId;
  final String provider;
  final void Function(ExternalSearchPage partial)? onUpdate;
  final Duration inactivityTimeout;
  final Completer<ExternalSearchPage> completer =
      Completer<ExternalSearchPage>();

  /// הגיעה תגובה כלשהי (חלקית/שגיאה) — מבטל את הניסיון החוזר.
  bool sawActivity = false;

  /// המופע שענה ראשון. הבקשה משוגרת ליעד יחיד, אבל ניסיון חוזר (retry)
  /// עלול להימסר למופע אחר — בלי הנעילה זרימת done=false צוברת כפולים.
  String? _responderInstanceId;

  Timer? _timer;

  /// נועל את הבקשה למופע העונה הראשון; תשובה ממופע אחר נדחית (false).
  bool bindResponder(String? instanceId) {
    if (instanceId == null) return true;
    _responderInstanceId ??= instanceId;
    return _responderInstanceId == instanceId;
  }

  _PendingExternalSearch({
    required this.pluginId,
    required this.provider,
    required this.onUpdate,
    required this.inactivityTimeout,
  }) {
    touch();
  }

  void touch() {
    _timer?.cancel();
    _timer = Timer(inactivityTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('External search provider stopped responding'),
        );
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
