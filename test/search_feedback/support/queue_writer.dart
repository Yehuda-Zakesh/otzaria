import 'dart:io';
import 'package:otzaria/search_feedback/search_feedback_queue.dart';
import 'package:otzaria/search_feedback/search_feedback_queue_lock.dart';

Future<void> main(List<String> args) async {
  final queue = SearchFeedbackQueue(
    () async => Directory(args[0]),
    clock: DateTime.now,
  );
  if (args[1] == 'lock') {
    final lock = await SearchFeedbackQueueLock.acquire('${args[0]}.lock');
    stdout.writeln('locked');
    await stdin.drain<void>();
    await lock.release();
    return;
  }
  final writer = int.parse(args[1]);
  for (var i = 0; i < 100; i++) {
    await queue.append(
      {'eventId': 'process_${writer}_$i', 'n': writer * 100 + i},
      {'app': 'otzaria'},
    );
  }
}
