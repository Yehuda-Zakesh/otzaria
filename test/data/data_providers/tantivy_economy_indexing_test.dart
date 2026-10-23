import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  test('ברירת המחדל רגילה; הבחירה מוחלת לפני חשיפת מנוע חלופי', () async {
    final first = _Engine();
    final provider = TantivyDataProvider.forTesting(Future.value(first));
    await provider.engine;
    expect(provider.isEconomyIndexing, isFalse);
    expect(first.calls, isEmpty);

    await provider.setEconomyIndexing(true);
    final replacement = _Engine()..gate = Completer<void>();
    provider.engine = Future.value(replacement);
    var exposed = false;
    final reopening = provider.engine.then((_) => exposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(replacement.calls, [true]);
    expect(exposed, isFalse);
    replacement.gate!.complete();
    await reopening;

    await provider.setEconomyIndexing(false);
    final normalReplacement = _Engine();
    provider.engine = Future.value(normalReplacement);
    await provider.engine;
    expect(provider.isEconomyIndexing, isFalse);
    expect(normalReplacement.calls, isEmpty);
  });

  test('כשל החלפה משמר את הבחירה והבקשה הבאה עדיין מתבצעת', () async {
    final engine = _Engine();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    await provider.setEconomyIndexing(true);
    engine.error = StateError('writer unavailable');
    await expectLater(provider.setEconomyIndexing(false), throwsStateError);
    expect(provider.isEconomyIndexing, isTrue);
    engine.error = null;
    await provider.setEconomyIndexing(false);
    expect(provider.isEconomyIndexing, isFalse);
  });

  test('שחזור בזמן החלפה מחיל את הבחירה גם על המנוע החדש', () async {
    final first = _Engine()..gate = Completer<void>();
    final provider = TantivyDataProvider.forTesting(Future.value(first));
    final toggling = provider.setEconomyIndexing(true);
    await Future<void>.delayed(Duration.zero);
    final replacement = _Engine();
    provider.engine = Future.value(replacement);
    first.gate!.complete();
    await toggling;
    expect(provider.isEconomyIndexing, isTrue);
    expect(replacement.calls, [true]);
  });

  test('שחזור בזמן כשל במנוע הישן מנסה את המנוע החדש', () async {
    final first = _Engine()
      ..gate = Completer<void>()
      ..error = StateError('disposed');
    final provider = TantivyDataProvider.forTesting(Future.value(first));
    final toggling = provider.setEconomyIndexing(true);
    await Future<void>.delayed(Duration.zero);
    final replacement = _Engine();
    provider.engine = Future.value(replacement);
    first.gate!.complete();
    await toggling;
    expect(provider.isEconomyIndexing, isTrue);
    expect(replacement.calls, [true]);
  });

  test('כשל בשחזור מצב סוגר את המנוע שלא ניתן לחשוף', () async {
    final provider = TantivyDataProvider.forTesting(Future.value(_Engine()));
    await provider.setEconomyIndexing(true);
    final replacement = _Engine()..error = StateError('writer unavailable');
    provider.engine = Future.value(replacement);
    await expectLater(provider.engine, throwsStateError);
    expect(replacement.disposed, isTrue);
    expect(provider.isEconomyIndexing, isTrue);
  });

  test('בקשות מהירות נשארות בסדר המשתמש', () async {
    final engine = _Engine()..gate = Completer<void>();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    final enabling = provider.setEconomyIndexing(true);
    final disabling = provider.setEconomyIndexing(false);
    await Future<void>.delayed(Duration.zero);
    expect(engine.calls, [true]);
    engine.gate!.complete();
    await Future.wait([enabling, disabling]);
    expect(engine.calls, [true, false]);
    expect(provider.isEconomyIndexing, isFalse);
  });
}

class _Engine implements SearchEngine {
  final calls = <bool>[];
  Completer<void>? gate;
  Object? error;
  bool disposed = false;

  @override
  Future<void> setEconomyIndexing({required bool enabled}) async {
    calls.add(enabled);
    await gate?.future;
    if (error != null) throw error!;
  }

  @override
  void dispose() => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: $invocation');
}
