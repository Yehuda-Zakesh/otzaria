import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;

import '../../support/search_engine_test_init.dart';

/// סכמה לא תואמת חייבת להיחסם לפני הפתיחה, כדי שלא תיספר כאינדקס פגום.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('TantivyDataProvider — אינדקס בסכמה לא תואמת', () {
    late Directory root;
    late Directory indexDir;
    late List<String> log;
    late DebugPrintCallback originalDebugPrint;

    setUp(() async {
      if (!engineReady) return;
      log = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => log.add(message ?? '');

      root = Directory.systemTemp.createTempSync('otzaria_incompatible_idx_');
      indexDir = Directory(p.join(root.path, 'index'))..createSync();
      await _writeIncompatibleIndex(indexDir);

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue(SettingsRepository.keyIndexPath, indexDir.path);
      AppPaths.debugOverrideDataRootPath(p.join(root.path, 'data'));
    });

    tearDown(() async {
      if (!engineReady) return;
      debugPrint = originalDebugPrint;
      await TantivyDataProvider.instance.dispose();
      AppPaths.debugOverrideDataRootPath(null);
      Settings.clearCache();
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // ב-Windows המנוע עלול להחזיק קבצים פתוחים בסיום הטסט.
      }
    });

    test(
      'rebuild_required: אינדקס הדיסק אינו נפתח, ושני קוראים חולקים אתחול אחד',
      () async {
        final compatibility = await checkIndexCompatibility(
          path: indexDir.path,
        );
        expect(compatibility.status, 'rebuild_required');

        // הסינגלטון חי בין הטסטים — פתיחה מאולצת מכוונת אותו ל-fixture הזה.
        final provider = TantivyDataProvider.instance;
        await provider.reopenIndex(force: true);
        final engines = await Future.wait([provider.engine, provider.engine]);

        expect(identical(engines[0], engines[1]), isTrue);
        expect(provider.indexCompatibility?.status, 'rebuild_required');
        expect(provider.requiresManualReindex, isTrue);
        expect(provider.isTempFallback, isTrue);
        expect(provider.activeIndexPath, isNot(indexDir.path));

        // ניסיון פתיחה היה מותיר סנטינל כשל ומדווח panic — שניהם חייבים
        // להיעדר, כלומר האינדקס הלא-תואם לא נגע בדיסק כלל.
        expect(
          File(p.join(root.path, '.engine_init_started')).existsSync(),
          isFalse,
          reason: 'סנטינל הפתיחה נכתב — האינדקס הלא-תואם נפתח בכל זאת',
        );
        expect(
          log.where((line) => line.contains('Failed to initialize')),
          isEmpty,
        );
        expect(log.where((line) => line.contains('PanicException')), isEmpty);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אחרי clear (מחיקת האינדקס) המנוע נפתח על הדיסק ואינו דורש rebuild',
      () async {
        final provider = TantivyDataProvider.instance;
        await provider.reopenIndex(force: true);
        expect(provider.isTempFallback, isTrue);

        await provider.clear();

        expect(provider.isTempFallback, isFalse);
        expect(provider.activeIndexPath, indexDir.path);
        expect(provider.requiresManualReindex, isFalse);
        expect(
          File(p.join(root.path, '.engine_init_started')).existsSync(),
          isFalse,
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}

/// מסיר שדה חובה מהסכמה ואת קובץ התאימות כדי לייצר אינדקס שאסור לפתוח.
Future<void> _writeIncompatibleIndex(Directory indexDir) async {
  final engine = await SearchEngine.newInstance(path: indexDir.path);
  await engine.addDocument(
    id: BigInt.one,
    title: 'ספר',
    reference: 'ספר א',
    topics: '/ספר',
    text: 'בראשית ברא',
    segment: BigInt.one,
    isPdf: false,
    filePath: 'id:1',
  );
  await engine.commit();
  engine.dispose();

  File(p.join(indexDir.path, 'otzaria_index_meta.json')).deleteSync();
  final metaFile = File(p.join(indexDir.path, 'meta.json'));
  final meta = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
  final schema = meta['schema'] as List<dynamic>;
  schema.removeWhere(
    (field) => (field as Map<String, dynamic>)['name'] == 'text',
  );
  metaFile.writeAsStringSync(jsonEncode(meta));
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;
}
