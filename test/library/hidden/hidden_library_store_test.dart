import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = HiddenLibraryStore();
  late _MemoryCacheProvider cache;

  setUp(() async {
    cache = _MemoryCacheProvider();
    await Settings.init(cacheProvider: cache);
  });

  test('שמירה וטעינה של הסתרות (issue #1448)', () async {
    await store.save(
      const HiddenLibrarySelection(
        bookKeys: {'o__10__שמות'},
        categoryPaths: {'/תנ"ך/תורה'},
      ),
    );

    final loaded = store.load();

    expect(loaded.bookKeys, {'o__10__שמות'});
    expect(loaded.categoryPaths, {'/תנ"ך/תורה'});
  });

  test('אין הסתרות שמורות — נטען ריק (issue #1448)', () {
    expect(store.load().isEmpty, isTrue);
  });

  test('ערך פגום אינו מסתיר דבר (issue #1448)', () async {
    await Settings.setValue<String>(
      HiddenLibraryStore.bookKeysSetting,
      'not json at all',
    );

    expect(
      store.load().bookKeys,
      isEmpty,
      reason: 'ברירת המחדל הבטוחה היא להציג, לא להעלים בשקט',
    );
  });

  test('ערכים ריקים מסוננים (issue #1448)', () async {
    await Settings.setValue<String>(
      HiddenLibraryStore.categoryPathsSetting,
      '["", "/תנ\\"ך", 7]',
    );

    expect(store.load().categoryPaths, {'/תנ"ך'});
  });

  test('כשל בכתיבה השנייה מחזיר את הבחירה שנשמרה בפועל', () async {
    await Settings.init(cacheProvider: _FailingCategoryCacheProvider());
    final result = await store.saveAndRead(
      const HiddenLibrarySelection(
        bookKeys: {'o__10__שמות'},
        categoryPaths: {'/תורה'},
      ),
    );

    expect(result.error, isA<StateError>());
    expect(result.actual.bookKeys, {'o__10__שמות'});
    expect(result.actual.categoryPaths, isEmpty);
  });

  test('סימון ממתין נשמר לפני הבחירה ושורד אתחול הגדרות', () async {
    await store.beginVisibilityIndexUpdate();
    await store.save(const HiddenLibrarySelection(bookKeys: {'book'}));
    await Settings.init(cacheProvider: cache);

    expect(store.load().bookKeys, {'book'});
    expect(store.hasPendingVisibilityIndex, isTrue);
    await store.clearPendingVisibilityIndex(store.visibilityRevision);
  });
}

class _FailingCategoryCacheProvider extends _MemoryCacheProvider {
  @override
  Future<void> setObject<T>(String key, T? value) async {
    if (key == HiddenLibraryStore.categoryPathsSetting) {
      throw StateError('second write failed');
    }
    await super.setObject<T>(key, value);
  }
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
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
