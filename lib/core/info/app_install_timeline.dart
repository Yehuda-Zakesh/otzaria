import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/app_paths.dart';

/// מקור תאריך ההתקנה.
enum InstallDateSource {
  /// נרשם בפועל בהפעלה הראשונה של האפליקציה.
  recorded,

  /// נגזר מזמן יצירת תיקיית הנתונים — הערכה, לא רישום.
  derived,

  /// אין מידע.
  unknown,
}

/// ציר הזמן של ההתקנה: מתי הותקנה, מתי עודכנה לאחרונה ומאיזו גרסה.
class AppInstallTimeline {
  final DateTime? installedAt;
  final InstallDateSource installedAtSource;
  final DateTime? updatedAt;
  final String? previousVersion;

  const AppInstallTimeline({
    this.installedAt,
    this.installedAtSource = InstallDateSource.unknown,
    this.updatedAt,
    this.previousVersion,
  });
}

/// רושם וקורא את ציר הזמן של ההתקנה.
///
/// [recordLaunch] נקרא בעליית האפליקציה מיד לאחר `Settings.init`, ומעדכן את
/// תאריך העדכון בכל פעם שגרסת האפליקציה משתנה מהגרסה שנרשמה קודם.
class AppInstallTimelineStore {
  static const String keyInstalledAt = 'key-app-installed-at';
  static const String keyInstalledAtSource = 'key-app-installed-at-source';
  static const String keyUpdatedAt = 'key-app-updated-at';
  static const String keyPreviousVersion = 'key-app-previous-version';

  /// הגרסה שנרשמה בהפעלה הקודמת. מפתח נפרד מ-`last_seen_app_version` (ניקוי
  /// הלוג) בכוונה — שינוי בסדר הקריאות ב-main לא ישבש את ציר הזמן.
  static const String keyTrackedVersion = 'key-app-tracked-version';

  const AppInstallTimelineStore._();

  /// גרסה שאינה נושאת מידע. `ErrorLogFile.appVersion` נופל אליה כשקריאת
  /// `PackageInfo` נכשלת, ורישומה היה מייצר "עדכון" מזויף בהפעלה הבאה.
  static const String _unknownVersion = 'unknown';

  /// מעדכן את ציר הזמן לגרסה הרצה כרגע. בטוח לקריאה בכל הפעלה.
  static Future<void> recordLaunch(
    String currentVersion, {
    DateTime? now,
  }) async {
    final version = currentVersion.trim();
    if (version.isEmpty || version == _unknownVersion) return;

    final timestamp = now ?? DateTime.now();
    try {
      if (_readString(keyInstalledAt) == null) {
        final derived = await _probeInstallDate(timestamp);
        // המקור נכתב ראשון: אם הכתיבה השנייה תיכשל, keyInstalledAt יישאר
        // חסר וההפעלה הבאה תרשום את שניהם מחדש. בסדר ההפוך היה נשאר תאריך
        // נגזר שמוצג כאילו נרשם בפועל.
        await Settings.setValue(
          keyInstalledAtSource,
          (derived == null
                  ? InstallDateSource.recorded
                  : InstallDateSource.derived)
              .name,
        );
        await Settings.setValue(
          keyInstalledAt,
          (derived ?? timestamp).toIso8601String(),
        );
      }

      final tracked = _readString(keyTrackedVersion);
      if (tracked == version) return;
      if (tracked != null) {
        await Settings.setValue(keyUpdatedAt, timestamp.toIso8601String());
        await Settings.setValue(keyPreviousVersion, tracked);
      }
      await Settings.setValue(keyTrackedVersion, version);
    } catch (error, stackTrace) {
      // ציר הזמן הוא מידע דיאגנוסטי בלבד — כשל בכתיבתו לא יעצור את העלייה.
      debugPrint(
        'AppInstallTimeline: recordLaunch failed: $error\n$stackTrace',
      );
    }
  }

  static AppInstallTimeline read() {
    final installedAt = _readDate(keyInstalledAt);
    return AppInstallTimeline(
      installedAt: installedAt,
      installedAtSource: installedAt == null
          ? InstallDateSource.unknown
          : _parseSource(_readString(keyInstalledAtSource)),
      updatedAt: _readDate(keyUpdatedAt),
      previousVersion: _readString(keyPreviousVersion),
    );
  }

  /// אומדן תאריך ההתקנה בהתקנות שקדמו למנגנון הרישום.
  ///
  /// Windows בלבד: `FileStat.changed` שם הוא זמן היצירה של התיקייה. ב-POSIX
  /// הוא זמן שינוי ה-inode ומשתנה בכל הוספת קובץ — חסר משמעות כאן.
  static Future<DateTime?> _probeInstallDate(DateTime now) async {
    if (!Platform.isWindows) return null;
    try {
      final root = Directory(await AppPaths.getDataRootPath());
      if (!await root.exists()) return null;
      final created = (await root.stat()).changed;
      if (created.isAfter(now)) return null;
      // שעון מערכת שהיה מאופס נותן 1970 — עדיף לרשום את ההפעלה הנוכחית.
      if (created.year < 2000) return null;
      return created;
    } catch (error) {
      debugPrint('AppInstallTimeline: install date probe failed: $error');
      return null;
    }
  }

  static InstallDateSource _parseSource(String? raw) {
    for (final source in InstallDateSource.values) {
      if (source.name == raw) return source;
    }
    return InstallDateSource.unknown;
  }

  static String? _readString(String key) {
    try {
      final value = Settings.getValue<String>(key)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      // Settings לא אותחל (בדיקות, פקודות headless).
      return null;
    }
  }

  static DateTime? _readDate(String key) {
    final raw = _readString(key);
    return raw == null ? null : DateTime.tryParse(raw);
  }
}
