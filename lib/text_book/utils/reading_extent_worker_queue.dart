import 'dart:async';

import 'package:flutter/foundation.dart';

/// מסדרת חישובי הערכה ומאפשרת לשחרר מטען שטרם התחיל להיספר.
class ReadingExtentWorkerQueue {
  Future<void> _tail = Future<void>.value();

  @visibleForTesting
  int debugStartedJobs = 0;

  /// מחזירה ידית שמאפשרת לבטל עבודה כל עוד היא ממתינה בתור.
  ReadingExtentWorkerJob<T> enqueue<T>(Future<T> Function() work) {
    final job = ReadingExtentWorkerJob<T>._(work);
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    unawaited(_run(previous, job, released));
    return job;
  }

  Future<void> _run<T>(
    Future<void> previous,
    ReadingExtentWorkerJob<T> job,
    Completer<void> released,
  ) async {
    await previous;
    try {
      final work = job._work;
      job._work = null;
      if (work == null) return;
      ++debugStartedJobs;
      try {
        job._result.complete(await work());
      } catch (error, stackTrace) {
        job._result.completeError(error, stackTrace);
      }
    } finally {
      released.complete();
    }
  }
}

class ReadingExtentWorkerJob<T> {
  ReadingExtentWorkerJob._(this._work);

  Future<T> Function()? _work;
  final _result = Completer<T?>();

  /// תוצאת החישוב, או null אם בוטל לפני תחילתו.
  Future<T?> get result => _result.future;
  bool get isPending => _work != null;

  /// חישוב שכבר התחיל משלים את תוצאתו; עבודה ממתינה משחררת גם את התוכן.
  bool cancel() {
    if (_work == null) return false;
    _work = null;
    _result.complete(null);
    return true;
  }
}
