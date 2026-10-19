import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:path/path.dart' as p;

/// `CacheProvider` לקריאה בלבד מעל תצלום של ההגדרות. כל ה-setters הם no-op.
class ReadOnlySettingsCache extends CacheProvider {
  ReadOnlySettingsCache(Map<String, dynamic> values)
    : _values = Map.unmodifiable(values);

  final Map<String, dynamic> _values;

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      getValue<bool>(key, defaultValue: defaultValue);

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      getValue<double>(key, defaultValue: defaultValue);

  @override
  int? getInt(String key, {int? defaultValue}) =>
      getValue<int>(key, defaultValue: defaultValue);

  @override
  String? getString(String key, {String? defaultValue}) =>
      getValue<String>(key, defaultValue: defaultValue);

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> setBool(String key, bool? value) async {}

  @override
  Future<void> setDouble(String key, double? value) async {}

  @override
  Future<void> setInt(String key, int? value) async {}

  @override
  Future<void> setString(String key, String? value) async {}

  @override
  Future<void> setObject<T>(String key, T? value) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removeAll() async {}
}

/// קורא את הגדרות המשתמש בלי להתנגש במופע הגרפי שרץ במקביל.
///
/// Hive נועל את תיבת ההגדרות בלעדית לכל התהליך (`app_preferences.lock` לצד
/// הקובץ), ולכן תהליך CLI שינסה לפתוח אותה ייכשל כל עוד אוצריא פתוחה.
/// הפתרון: להעתיק את קובץ התיבה לתיקייה זמנית ולפתוח את *העותק*. פורמט
/// ה-Hive הוא לוג של פריימים, וקריאה של עותק שנלקח תוך כתיבה מתאוששת ע"י
/// קטימת הפריים החלקי בסוף — הערך הגרוע ביותר הוא הגדרה אחת שהשתנתה
/// בשבריר שנייה שלפני הקריאה.
///
/// ההפרדה עובדת בין תהליכים בלבד. בתוך תהליך שבו התיבה כבר פתוחה
/// (המופע הגרפי) [read] מסרב לפעול — ראה את הבדיקה בתחילתו.
/// כמו כן [read] מפנה את נתיב Hive הגלובלי ל-staging שנמחק בסופו, ולכן
/// אינו מיועד לתהליך שממשיך לפתוח boxes אחר כך.
class SettingsSnapshot {
  const SettingsSnapshot._();

  /// שם קובץ התיבה על הדיסק, כפי ש-Hive יוצר אותו מ-[HiveCache.keyName].
  static String get boxFileName => '${HiveCache.keyName}.hive';

  /// מאתחל את `Settings` מתצלום קריאה-בלבד של הגדרות המשתמש.
  ///
  /// מחזיר `true` כשההגדרות האמיתיות נטענו, ו-`false` כשלא נמצאו או שהקריאה
  /// נכשלה — אז `Settings` מאותחל ריק והקוראים נופלים לברירות המחדל.
  static Future<bool> initializeReadOnly() async {
    Map<String, dynamic>? values;
    try {
      values = await read();
    } catch (error, stackTrace) {
      debugPrint('SettingsSnapshot: read failed: $error\n$stackTrace');
    }
    await Settings.init(cacheProvider: ReadOnlySettingsCache(values ?? {}));
    return values != null;
  }

  /// מעתיק את תיבת ההגדרות לתיקייה זמנית וקורא ממנה את כל הזוגות.
  /// מחזיר null כשקובץ התיבה אינו קיים או כשהתיבה פתוחה בתהליך הזה.
  @visibleForTesting
  static Future<Map<String, dynamic>?> read({String? dataRootPath}) async {
    // `Hive.openBox` מחזיר תיבה פתוחה קיימת לפי שם ומתעלם מהנתיב, ואז
    // הסגירה כאן הייתה סוגרת את התיבה החיה ומפילה כל קריאה להגדרות.
    if (Hive.isBoxOpen(HiveCache.keyName)) {
      debugPrint('SettingsSnapshot: live box open in-process, skipping');
      return null;
    }

    final root = dataRootPath ?? await AppPaths.getDataRootPath();
    final source = File(p.join(root, boxFileName));
    if (!await source.exists()) return null;

    final staging = await Directory.systemTemp.createTemp('otzaria-settings-');
    try {
      await source.copy(p.join(staging.path, boxFileName));
      Hive.init(staging.path);
      final box = await Hive.openBox<dynamic>(HiveCache.keyName);
      try {
        return <String, dynamic>{
          for (final key in box.keys)
            if (key is String) key: box.get(key),
        };
      } finally {
        // חייב להיקרא לפני מחיקת ה-staging: תיבה פתוחה מחזיקה את הקובץ
        // ב-Windows, המחיקה נכשלת, והעותק — הכולל סודות כמו hash סיסמת
        // המצב המוגן ואישורי Google — נשאר ב-%TEMP% לצמיתות.
        await box.close();
      }
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (error) {
        debugPrint('SettingsSnapshot: staging cleanup failed: $error');
      }
    }
  }
}
