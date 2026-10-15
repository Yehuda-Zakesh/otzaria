import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';

String? _hiveRootOverride;

/// התיקייה שתחתיה יושבים שורשי ה-Hive הפרטיים של חלונות משניים.
///
/// `<dataRoot>/windows/slot-N`. אינה מגובה ואינה נטענת בהפעלה קרה — ראו
/// [deleteStaleWindowRoots].
const String windowRootsDirName = 'windows';

/// מפנה את קובצי ה-Hive של החלון הזה לתיקייה נפרדת.
///
/// ⚠️ **רק Hive.** `hive_ce` נועל את קובצי ה-`.lock` בלעדית, והנעילה היא
/// פר-handle: שני חלונות באותו תהליך נכשלים בדיוק כמו שני תהליכים. לכן
/// לחלון משני יש קובצי Hive משלו.
///
/// אסור להפנות בשבילו את **שורש הנתונים כולו** — שם יושבים גם התוספים
/// (`<dataRoot>/plugins`), תיקיית WebView2 ומסדי הנתונים של המשתמש.
/// הפניה גורפת רוקנה את תפריט הכלים בחלונות משניים וגרמה לכרטיסיות תוסף
/// להיעלם במקום לעבור.
void configureHiveRootForWindow(String path) {
  _hiveRootOverride = path;
}

/// שורש קובצי ה-Hive. זהה לשורש הנתונים, למעט חלונות משניים.
Future<String> hiveRootPath() async =>
    _hiveRootOverride ?? await AppPaths.getDataRootPath();

/// מוחק את שורשי ה-Hive הפרטיים שנשארו מהפעלה קודמת.
///
/// ⚠️ נקרא **רק** מהחלון הראשון ובהפעלה קרה, לפני שנפתח חלון משני. באותו
/// רגע אין אף חלון משני חי ולכן כל התיקיות שם הן שאריות; קריאה בכל עת אחרת
/// תמחוק קובצי Hive שחלון חי פתח.
///
/// כשל מדולג בשקט: אי אפשר למחוק תיקייה שקובץ בה נעול, וזה לא מצדיק לעצור
/// את העלייה.
///
/// The folder is renamed aside, which is instant whatever its size, and
/// deleted in the background; a window opened meanwhile gets a fresh folder.
Future<void> deleteStaleWindowRoots() async {
  try {
    final dataRoot = await AppPaths.getDataRootPath();
    final root = Directory(p.join(dataRoot, windowRootsDirName));
    if (await root.exists()) {
      final stalePath =
          '${root.path}$_staleSuffix$pid-${DateTime.now().microsecondsSinceEpoch}';
      await root.rename(stalePath);
    }
    pendingStaleRootsDeletion = _deleteRenamedRoots(dataRoot);
  } catch (e) {
    debugPrint('⚠️ deleteStaleWindowRoots failed: $e');
  }
}

const String _staleSuffix = '.stale-';

/// The background deletion started by [deleteStaleWindowRoots].
@visibleForTesting
Future<void>? pendingStaleRootsDeletion;

/// Also removes folders an earlier deletion could not finish.
Future<void> _deleteRenamedRoots(String dataRoot) async {
  try {
    await for (final entity in Directory(dataRoot).list()) {
      if (entity is! Directory ||
          !p
              .basename(entity.path)
              .startsWith('$windowRootsDirName$_staleSuffix')) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } catch (e) {
        debugPrint('⚠️ stale window root not deleted: $e');
      }
    }
  } catch (e) {
    debugPrint('⚠️ stale window roots scan failed: $e');
  }
}

/// A cache access provider class for shared preferences using Hive library
class HiveCache extends CacheProvider {
  Box? _preferences;
  static const String keyName = 'app_preferences';

  @override
  Future<void> init() async {
    if (!kIsWeb) {
      final defaultDirectory = await hiveRootPath();
      _preferences = await Hive.openBox<dynamic>(
        keyName,
        path: defaultDirectory,
      );
    }
    // ⚠️ החלת שינוי מרוחק כותבת ל-box **ישירות** ולא דרך ה-setters, כדי
    // שהיא לא תשודר בחזרה לחלון שממנו באה. ראו [SettingsSync].
    SettingsSync.instance.applyLocally = (key, value) async {
      if (value == null) {
        await _preferences?.delete(key);
      } else {
        await _preferences?.put(key, value);
      }
    };
    SettingsSync.instance.clearLocally = () async {
      await _preferences?.clear();
    };
  }

  @override
  bool? getBool(String key, {bool? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  double? getDouble(String key, {double? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  int? getInt(String key, {int? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  String? getString(String key, {String? defaultValue}) {
    return _preferences?.get(key, defaultValue: defaultValue) ?? defaultValue;
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    await _preferences?.put(key, value);
    SettingsSync.instance.broadcastChange(key, value);
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    await _preferences?.put(key, value);
    SettingsSync.instance.broadcastChange(key, value);
  }

  @override
  Future<void> setInt(String key, int? value) async {
    await _preferences?.put(key, value);
    SettingsSync.instance.broadcastChange(key, value);
  }

  @override
  Future<void> setString(String key, String? value) async {
    await _preferences?.put(key, value);
    SettingsSync.instance.broadcastChange(key, value);
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    await _preferences?.put(key, value);
    SettingsSync.instance.broadcastChange(key, value);
  }

  @override
  bool containsKey(String key) {
    return _preferences?.containsKey(key) ?? false;
  }

  @override
  Set getKeys() {
    return _preferences?.keys.toSet() ?? {};
  }

  @override
  Future<void> remove(String key) async {
    if (containsKey(key)) {
      await _preferences?.delete(key);
      SettingsSync.instance.broadcastChange(key, null);
    }
  }

  @override
  Future<void> removeAll() async {
    await _preferences?.deleteAll(getKeys().cast<String>());
    // ⚠️ גם מחיקה היא שינוי. בלי השידור החלון השני ממשיך עם הערכים הישנים
    // בזיכרון, וכל שמירה שלו כותבת אותם בחזרה — כלומר האיפוס מתבטל.
    SettingsSync.instance.broadcastReset();
  }

  /// מחיקת כל ההגדרות, בהמתנה לסיומה.
  ///
  /// `Settings.clearCache` של החבילה הוא `void` ואינו ממתין ל-Future של
  /// המחיקה: איפוס דרכו מתחיל בנייה מחדש בזמן שהמחיקה עוד רצה, וברירות
  /// המחדל שנכתבות מיד אחריו נמחקות איתה.
  static Future<void> clearAllPreferences() async {
    if (!Hive.isBoxOpen(keyName)) return;
    await Hive.box<dynamic>(keyName).clear();
    SettingsSync.instance.broadcastReset();
  }

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    var value = _preferences?.get(key);
    if (value is T) {
      return value;
    }
    return defaultValue;
  }
}
