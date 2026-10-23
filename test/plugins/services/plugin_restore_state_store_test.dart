import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';

void main() {
  const key = (pluginId: 'p', instanceId: 'i1');
  final store = PluginRestoreStateStore.instance;

  tearDown(() => store.remove(key));

  test('שומר ומחזיר ערך JSON', () {
    store.set(key, {'screen': 'list', 'top': 120});
    expect(store.has(key), isTrue);
    expect(store.stateOf(key), {'screen': 'list', 'top': 120});
    expect(store.jsonOf(key), '{"screen":"list","top":120}');
  });

  test('null מוחק', () {
    store.set(key, 1);
    store.set(key, null);
    expect(store.has(key), isFalse);
    expect(store.stateOf(key), isNull);
  });

  test('ערך גדול מ-64KB נדחה ואינו מחליף את הקיים', () {
    store.set(key, 'small');
    expect(
      () => store.set(key, 'x' * PluginRestoreStateStore.maxStateBytes),
      throwsArgumentError,
    );
    expect(store.stateOf(key), 'small');
  });

  test('ערך שאינו JSON נדחה', () {
    expect(() => store.set(key, Object()), throwsArgumentError);
  });

  test('זריעה מסשן מתעלמת מ-JSON פגום', () {
    store.seed(key, '{not json');
    expect(store.has(key), isFalse);
    store.seed(key, '[1,2]');
    expect(store.stateOf(key), [1, 2]);
  });

  test('removeInstanceId מוחק לפי מזהה המופע בלבד', () {
    const other = (pluginId: 'q', instanceId: 'reader-1');
    store.set(other, true);
    store.removeInstanceId('reader-1');
    expect(store.has(other), isFalse);
  });

  test('המפתח הוא PluginInstanceKey', () {
    const PluginInstanceKey typed = key;
    store.set(typed, 'v');
    expect(store.stateOf(key), 'v');
  });

  group('גבול כולל', () {
    PluginInstanceKey k(int i) => (pluginId: 'bound', instanceId: 'i$i');
    tearDown(() {
      for (var i = 0; i < 200; i++) {
        store.remove(k(i));
      }
    });

    test('מעבר למספר הרשומות — הוותיק נמחק', () {
      for (var i = 0; i <= PluginRestoreStateStore.maxEntries; i++) {
        store.set(k(i), i);
      }
      expect(store.length, PluginRestoreStateStore.maxEntries);
      expect(store.has(k(0)), isFalse);
      expect(store.has(k(PluginRestoreStateStore.maxEntries)), isTrue);
    });

    test('עדכון מחזיר רשומה לסוף התור', () {
      for (var i = 0; i < PluginRestoreStateStore.maxEntries; i++) {
        store.set(k(i), i);
      }
      store.set(k(0), 'again');
      store.set(k(999), 'new');
      expect(store.has(k(0)), isTrue);
      expect(store.has(k(1)), isFalse);
    });

    test('מעבר לגודל הכולל — נמחקים ותיקים עד שחוזרים לגבול', () {
      final big = 'x' * (PluginRestoreStateStore.maxStateBytes - 10);
      for (var i = 0; i < 40; i++) {
        store.seed(k(i), '"$big"');
      }
      expect(
        store.totalBytes,
        lessThanOrEqualTo(PluginRestoreStateStore.maxTotalBytes),
      );
      expect(store.has(k(39)), isTrue);
      expect(store.has(k(0)), isFalse);
      store.remove(k(39));
      expect(store.has(k(39)), isFalse);
    });
  });
}
