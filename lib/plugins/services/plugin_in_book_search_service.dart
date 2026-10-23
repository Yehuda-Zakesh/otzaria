import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';

typedef InBookSearchEventDispatcher =
    Future<void> Function(
      String pluginId,
      String topic,
      Map<String, dynamic> payload, {
      bool preferBackground,
    });

/// ספקי חיפוש-בתוך-ספר של תוספים.
///
/// אוצריא אינה מדברת עם מנועי חיפוש חיצוניים בעצמה (ראו למשל שירות
/// HebrewBooks — התקשורת איתו שייכת לתוסף בלבד). במקום זאת תוסף נרשם כספק
/// עבור provider חיצוני ('hebrewbooks'), הקורא שולח אליו בקשה כאירוע ממוקד
/// `reader.inBookSearch.requested`, והתוסף עונה בקריאת bridge
/// `reader.respondInBookSearch` עם עמודי ההתאמה.
class PluginInBookSearchService {
  PluginInBookSearchService._()
    : _dispatch = ((pluginId, topic, payload, {preferBackground = false}) =>
          PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
            pluginId,
            topic,
            payload,
            preferBackground: preferBackground,
          ));
  static final PluginInBookSearchService instance =
      PluginInBookSearchService._();

  @visibleForTesting
  PluginInBookSearchService.forTesting(this._dispatch);

  static const requestTopic = 'reader.inBookSearch.requested';
  static const _timeout = Duration(seconds: 30);

  final Map<String, String> _providerToPlugin = {};
  final Map<String, _PendingInBookSearch> _pending = {};
  final InBookSearchEventDispatcher _dispatch;
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
    debugPrint('PluginInBookSearchService: $pluginId provides "$provider"');
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
          StateError('In-book search provider is no longer available'),
        );
      }
    }
  }

  /// שולח שאילתה לספק של [provider] ומחזיר את עמודי ההתאמה שלו.
  /// זורק [TimeoutException] כשהתוסף לא ענה בזמן, או [StateError] כשאין ספק.
  Future<ExternalBookMatches> search({
    required String provider,
    required Object externalId,
    required String query,
  }) async {
    final pluginId = _providerToPlugin[provider];
    if (pluginId == null) {
      throw StateError('No in-book search provider for "$provider"');
    }
    final requestId = 'ibs-${++_requestCounter}';
    final pending = _PendingInBookSearch(pluginId);
    final completer = pending.completer;
    _pending[requestId] = pending;
    final eventPayload = {
      'requestId': requestId,
      'provider': provider,
      'externalId': externalId,
      'query': query,
    };
    Timer? retryTimer;
    try {
      // לא ממתינים ל-dispatch לפני ההאזנה: מסלול ההעֲרָה של התוסף עשוי
      // לקחת זמן, והטיימאאוט חייב למדוד את הבקשה כולה עם מאזין מחובר.
      final dispatch = _dispatch(
        pluginId,
        requestTopic,
        eventPayload,
        preferBackground: true,
      );
      unawaited(
        dispatch.catchError((Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        }),
      );
      // אירוע שנמסר לדף שעוד לא רשם מאזינים (טעינה-מחדש בזמן העֲרָה) אובד
      // בשקט — משגרים שוב פעם אחת אחרי שקט קצר; הבקשה אידמפוטנטית.
      retryTimer = Timer(const Duration(seconds: 8), () {
        if (completer.isCompleted) return;
        debugPrint('PluginInBookSearchService: retrying $requestId');
        unawaited(
          _dispatch(
            pluginId,
            requestTopic,
            eventPayload,
            preferBackground: true,
          ).catchError((_) {}),
        );
      });
      return await completer.future.timeout(_timeout);
    } finally {
      retryTimer?.cancel();
      _pending.remove(requestId);
    }
  }

  /// תשובת התוסף לבקשה. [pages] מבוססי-1; תשובה זרה, שפגה, או ממופע אחר
  /// של התוסף ([instanceId]) נדחית.
  bool respond(
    String pluginId,
    String requestId, {
    List<int> pages = const [],
    List<String> matchedTerms = const [],
    String query = '',
    String? error,
    String? instanceId,
  }) {
    final pending = _pending[requestId];
    if (pending == null ||
        pending.pluginId != pluginId ||
        pending.completer.isCompleted) {
      return false;
    }
    if (!pending.bindResponder(instanceId)) return false;
    _pending.remove(requestId);
    final completer = pending.completer;
    if (error != null && error.isNotEmpty) {
      completer.completeError(StateError(error));
      return true;
    }
    completer.complete(
      ExternalBookMatches(
        pages: pages,
        matchedTerms: matchedTerms,
        query: query,
      ),
    );
    return true;
  }
}

class _PendingInBookSearch {
  final String pluginId;
  final Completer<ExternalBookMatches> completer =
      Completer<ExternalBookMatches>();

  /// המופע שענה ראשון — ניסיון חוזר (retry) עלול להימסר למופע אחר.
  String? _responderInstanceId;

  _PendingInBookSearch(this.pluginId);

  /// נועל את הבקשה למופע העונה הראשון; תשובה ממופע אחר נדחית (false).
  bool bindResponder(String? instanceId) {
    if (instanceId == null) return true;
    _responderInstanceId ??= instanceId;
    return _responderInstanceId == instanceId;
  }
}
