import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_extent_worker_queue.dart';

void main() {
  test('ביטול משחרר עבודה ממתינה בלי להמתין לחישוב הקודם', () async {
    final queue = ReadingExtentWorkerQueue();
    final running = Completer<int>();
    final first = queue.enqueue(() => running.future);
    await Future<void>.delayed(Duration.zero);
    expect(first.isPending, isFalse);
    expect(first.cancel(), isFalse);
    var cancelledCalls = 0;
    final second = queue.enqueue(() async => ++cancelledCalls);
    expect(second.isPending, isTrue);
    expect(second.cancel(), isTrue);
    expect(second.isPending, isFalse);
    expect(await second.result, isNull);
    expect(queue.debugStartedJobs, 1);
    running.complete(7);
    expect(await first.result, 7);
    await Future<void>.delayed(Duration.zero);
    expect(cancelledCalls, 0);
    expect(queue.debugStartedJobs, 1);
    expect(second.cancel(), isFalse);
  });

  test('כשל של חישוב מגיע למבקש ואינו עוצר את התור', () async {
    final queue = ReadingExtentWorkerQueue();
    final failed = queue.enqueue<int>(() async => throw StateError('count'));
    final failure = expectLater(failed.result, throwsStateError);
    final next = queue.enqueue(() async => 42);
    await failure;
    expect(await next.result, 42);
    expect(queue.debugStartedJobs, 2);
  });
}
