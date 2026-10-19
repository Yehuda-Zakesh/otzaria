import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/internet_connectivity.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// תמונת מצב הקישוריות שאוצריא מדווחת לתוספים.
@immutable
class ConnectivitySnapshot {
  const ConnectivitySnapshot({
    required this.isOfflineMode,
    required this.hasNetwork,
  });

  /// המשתמש סימן "ללא גישה לאינטרנט" בהגדרות.
  final bool isOfflineMode;

  /// נמצא חיבור בפועל בבדיקה. במצב מנותק תמיד `false` — הבדיקה כלל אינה רצה.
  final bool hasNetwork;

  /// הדגל היחיד שתוסף צריך כדי להחליט אם להציג יכולת מקוונת.
  bool get isOnline => !isOfflineMode && hasNetwork;

  Map<String, Object?> toJson() => {
    'isOfflineMode': isOfflineMode,
    'hasNetwork': hasNetwork,
    'isOnline': isOnline,
  };
}

/// מספק מצב קישוריות יציב לזמן קצר, בלי קריאת רשת לכל שאילתה.
///
/// התוצאה נשמרת בחלון זמן קצוב כדי למנוע הבהוב בין רינדורים, ומתחדשת לאחריו.
/// במצב מנותק לא מתבצעת בדיקה כלל.
class ConnectivityStatusService {
  ConnectivityStatusService({
    bool Function()? offlineModeReader,
    Future<bool> Function()? networkProbe,
    Duration cacheTtl = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _offlineModeReader = offlineModeReader ?? _readOfflineModeSetting,
       _networkProbe = networkProbe ?? _probeOtzariaTargets,
       _cacheTtl = cacheTtl,
       _clock = clock ?? DateTime.now,
       assert(!cacheTtl.isNegative);

  static ConnectivityStatusService instance = ConnectivityStatusService();

  final bool Function() _offlineModeReader;
  final Future<bool> Function() _networkProbe;
  final Duration _cacheTtl;
  final DateTime Function() _clock;

  bool? _cachedHasNetwork;
  DateTime? _cachedAt;
  Future<bool>? _pendingProbe;

  static bool _readOfflineModeSetting() =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  static Future<bool> _probeOtzariaTargets() =>
      hasInternetConnection(targets: kOtzariaProbeTargets);

  /// מצב הקישוריות הנוכחי. תוצאה טרייה נשמרת לזמן קצוב בין קריאות.
  Future<ConnectivitySnapshot> snapshot({bool forceRefresh = false}) async {
    if (_offlineModeReader()) {
      // לא מקבעים `false` בקאש: המשתמש עשוי לכבות את המצב המנותק תוך כדי
      // ריצה, ואז הבדיקה הראשונה אמורה לרוץ באמת.
      return const ConnectivitySnapshot(isOfflineMode: true, hasNetwork: false);
    }
    final hasNetwork = await _resolveHasNetwork(forceRefresh: forceRefresh);
    if (_offlineModeReader()) {
      return const ConnectivitySnapshot(isOfflineMode: true, hasNetwork: false);
    }
    return ConnectivitySnapshot(isOfflineMode: false, hasNetwork: hasNetwork);
  }

  /// תמונת המצב אם היא כבר מוכנה, בלי להמתין לבדיקה. `null` = טרם הוכרעה.
  ConnectivitySnapshot? get cached {
    if (_offlineModeReader()) {
      return const ConnectivitySnapshot(isOfflineMode: true, hasNetwork: false);
    }
    final hasNetwork = _freshCachedHasNetwork;
    if (hasNetwork == null) return null;
    return ConnectivitySnapshot(isOfflineMode: false, hasNetwork: hasNetwork);
  }

  /// מפעילה את הבדיקה ברקע בלי להמתין לה.
  void prewarm() {
    if (_offlineModeReader()) return;
    unawaited(_resolveHasNetwork());
  }

  /// מצב הקישוריות ל-payload של עליית תוסף — **סינכרוני, בלי המתנה לרשת**.
  ///
  /// כשהבדיקה טרם הוכרעה מוחזר `null` והיא מופעלת ברקע. אסור להמתין כאן:
  /// המתנה לרשת מעכבת את הצגת התוסף בכמה שניות אצל מי שאין לו חיבור.
  Map<String, Object?> bootPayload() {
    final snapshot = cached;
    if (snapshot != null) return snapshot.toJson();
    prewarm();
    return {'isOfflineMode': false, 'hasNetwork': null, 'isOnline': null};
  }

  bool? get _freshCachedHasNetwork {
    final cached = _cachedHasNetwork;
    final cachedAt = _cachedAt;
    if (cached == null || cachedAt == null) return null;
    final age = _clock().difference(cachedAt);
    if (age.isNegative || age >= _cacheTtl) return null;
    return cached;
  }

  Future<bool> _resolveHasNetwork({bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _freshCachedHasNetwork;
      if (cached != null) return Future.value(cached);
    }

    // בדיקות מקבילות מתלכדות לבדיקה אחת — פתיחת כמה תוספים יחד לא פותחת
    // כמה חיבורים.
    final pending = _pendingProbe;
    if (pending != null) return pending;

    final probe = _runProbe();
    _pendingProbe = probe;
    // הניקוי אחרי ההשמה בכוונה: כשל סינכרוני של הבדיקה מסיים את `probe` עוד
    // לפני שהושם, ו-finally בתוך `_runProbe` היה משאיר כאן Future תקוע לנצח.
    unawaited(probe.whenComplete(() => _pendingProbe = null));
    return probe;
  }

  Future<bool> _runProbe() async {
    try {
      final result = await _networkProbe();
      _cachedHasNetwork = result;
      _cachedAt = _clock();
      return result;
    } catch (_) {
      _cachedHasNetwork = false;
      _cachedAt = _clock();
      return false;
    }
  }

  /// איפוס לבדיקות בלבד.
  @visibleForTesting
  void resetCache() {
    _cachedHasNetwork = null;
    _cachedAt = null;
    _pendingProbe = null;
  }
}
