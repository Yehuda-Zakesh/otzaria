import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'disable waits for blocked replacement restore and wins last',
    () async {
      final first = _Probe();
      final provider = TantivyDataProvider.forTesting(Future.value(first));
      await provider.setEconomyIndexing(true);
      final next = _Probe()..gate = Completer<void>();
      provider.engine = Future.value(next);
      final opening = provider.engine;
      await _tick();
      final disabling = provider.setEconomyIndexing(false);
      await _tick();
      expect(provider.isEconomyIndexing, true);
      expect(next.calls, [true]);
      next.gate!.complete();
      await opening;
      await disabling;
      expect(next.calls, [true, false]);
      expect(provider.isEconomyIndexing, false);
    },
  );

  test(
    'failed first update does not poison queued opposite update',
    () async {
      final native = _Probe()..failFirst = true;
      final provider = TantivyDataProvider.forTesting(Future.value(native));
      final first = provider.setEconomyIndexing(true);
      final failure = expectLater(first, throwsStateError);
      final second = provider.setEconomyIndexing(false);
      await failure;
      await second;
      expect(native.calls, [true, false]);
      expect(provider.isEconomyIndexing, false);
    },
  );

  test('two replacements while a native update is in progress', () async {
    final a = _Probe()..gate = Completer<void>();
    final provider = TantivyDataProvider.forTesting(Future.value(a));
    final toggling = provider.setEconomyIndexing(true);
    await _tick();
    final b = _Probe()..gate = Completer<void>();
    provider.engine = Future.value(b);
    a.gate!.complete();
    await _tick();
    expect(b.calls, [true]);
    final c = _Probe();
    provider.engine = Future.value(c);
    b.gate!.complete();
    await toggling;
    expect(c.calls, [true]);
    expect(provider.isEconomyIndexing, true);
  });

  test(
    'restore failure closes replacement, next replacement can recover',
    () async {
      final provider = TantivyDataProvider.forTesting(Future.value(_Probe()));
      await provider.setEconomyIndexing(true);
      final failed = _Probe()..failFirst = true;
      provider.engine = Future.value(failed);
      await expectLater(provider.engine, throwsStateError);
      expect(failed.disposed, true);
      final recovered = _Probe();
      provider.engine = Future.value(recovered);
      expect(await provider.engine, same(recovered));
      expect(recovered.calls, [true]);
      await provider.setEconomyIndexing(false);
      expect(recovered.calls, [true, false]);
    },
  );
}

class _Probe implements SearchEngine {
  final calls = <bool>[];
  Completer<void>? gate;
  bool failFirst = false;
  bool disposed = false;
  @override
  Future<void> setEconomyIndexing({required bool enabled}) async {
    calls.add(enabled);
    await gate?.future;
    if (failFirst && calls.length == 1) {
      throw StateError('injected native error');
    }
  }

  @override
  void dispose() {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
