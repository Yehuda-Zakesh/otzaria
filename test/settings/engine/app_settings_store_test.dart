import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _SlowClearCacheProvider extends MemoryCacheProvider {
  final clearGate = Completer<void>();

  @override
  Future<void> removeAll() async {
    await clearGate.future;
    await super.removeAll();
  }
}

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('getValue returns the default for a missing key', () {
    expect(Settings.getValue<int>('missing', defaultValue: 7), 7);
    expect(Settings.containsKey('missing'), isFalse);
  });

  test('getValue returns the default when the stored type differs', () async {
    await Settings.setValue<String>('key', 'text');
    expect(Settings.getValue<int>('key', defaultValue: 3), 3);
    expect(Settings.getValue<String>('key'), 'text');
  });

  test('setValue with null removes the key', () async {
    await Settings.setValue<bool>('flag', true);
    expect(Settings.containsKey('flag'), isTrue);

    await Settings.setValue<bool?>('flag', null);
    expect(Settings.containsKey('flag'), isFalse);
  });

  test(
    'clearCache completes only after the provider finished clearing',
    () async {
      final provider = _SlowClearCacheProvider();
      await Settings.init(cacheProvider: provider);
      await Settings.setValue<String>('key', 'value');

      var cleared = false;
      final clearing = Settings.clearCache().then((_) => cleared = true);
      await pumpEventQueue();
      expect(cleared, isFalse);

      provider.clearGate.complete();
      await clearing;
      expect(Settings.containsKey('key'), isFalse);
    },
  );
}
