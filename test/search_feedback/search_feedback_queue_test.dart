import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_queue.dart';

void main() {
  late Directory dir;
  var tick = 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sf_queue');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  SearchFeedbackQueue makeQueue({
    int maxEvents = 5000,
    int maxBytes = 5 * 1024 * 1024,
    int segmentEvents = 100,
  }) => SearchFeedbackQueue(
    () async => dir,
    clock: () => DateTime.utc(2026, 10, 2).add(Duration(seconds: tick++)),
    maxEvents: maxEvents,
    maxBytes: maxBytes,
    segmentEvents: segmentEvents,
  );

  Map<String, Object?> event(int i) => {'eventId': 'event_$i', 'n': i};
  const context = {'app': 'otzaria'};

  test(
    'appends JSONL lines with a context header and reads them back',
    () async {
      final queue = makeQueue();
      await queue.append(event(1), context);
      await queue.append(event(2), context);
      final names = await queue.sealAndList();
      expect(names, hasLength(1));

      final lines = await File('${dir.path}/${names.single}').readAsLines();
      expect(jsonDecode(lines.first), context);
      expect(lines, hasLength(3));

      final batch = (await queue.read(names.single))!;
      expect(batch.eventLines.map((l) => jsonDecode(l)['n']), [1, 2]);
    },
  );

  test('a new context or a full segment opens a new segment', () async {
    final queue = makeQueue(segmentEvents: 2);
    for (var i = 0; i < 5; i++) {
      await queue.append(event(i), context);
    }
    await queue.append(event(9), {'app': 'other'});
    expect(await queue.sealAndList(), hasLength(4));
    expect(queue.eventCount, 6);
  });

  test('event cap drops the oldest segments', () async {
    final queue = makeQueue(maxEvents: 10, segmentEvents: 4);
    for (var i = 0; i < 30; i++) {
      await queue.append(event(i), context);
    }
    expect(queue.eventCount, lessThanOrEqualTo(10));
    final names = await queue.sealAndList();
    final last = await queue.read(names.last);
    expect(jsonDecode(last!.eventLines.last)['n'], 29, reason: 'newest kept');
    final first = await queue.read(names.first);
    expect(jsonDecode(first!.eventLines.first)['n'], greaterThan(0));
  });

  test('byte cap drops the oldest segments', () async {
    final queue = makeQueue(maxBytes: 2000, segmentEvents: 3);
    for (var i = 0; i < 50; i++) {
      await queue.append({...event(i), 'pad': 'x' * 100}, context);
    }
    expect(queue.byteCount, lessThanOrEqualTo(2000));
  });

  test('state survives a reload from disk', () async {
    final first = makeQueue();
    await first.append(event(1), context);
    await first.append(event(2), context);
    final reloaded = makeQueue();
    await reloaded.load();
    expect(reloaded.eventCount, 2);
  });

  test('split keeps order; a single event is dropped', () async {
    final queue = makeQueue();
    for (var i = 0; i < 4; i++) {
      await queue.append(event(i), context);
    }
    final name = (await queue.sealAndList()).single;
    await queue.split(name);
    final parts = await queue.sealAndList();
    expect(parts, hasLength(2));
    final firstPart = await queue.read(parts.first);
    expect(firstPart!.eventLines.map((l) => jsonDecode(l)['n']), [0, 1]);

    final single = makeQueue();
    await single.purge();
    await single.resume();
    await single.append(event(7), context);
    final only = (await single.sealAndList()).single;
    await single.split(only);
    expect(single.isEmpty, isTrue);
  });

  test('purge removes every queue file', () async {
    final queue = makeQueue();
    await queue.append(event(1), context);
    await queue.purge();
    expect(queue.isEmpty, isTrue);
    expect(dir.listSync(), isEmpty);
  });
  test('writers in separate processes cannot race a sender', () async {
    final received = <int>{};
    var done = false;
    final sender = makeQueue();
    final processes = await Future.wait([
      for (var i = 0; i < 2; i++)
        Process.start('dart', [
          '--packages=.dart_tool/package_config.json',
          'test/search_feedback/support/queue_writer.dart',
          dir.path,
          '$i',
        ]),
    ]);
    final finished =
        Future.wait([for (final process in processes) process.exitCode]).then((
          codes,
        ) {
          done = true;
          return codes;
        });
    final output = Future.wait([
      for (final process in processes)
        Future.wait([
          process.stdout.transform(utf8.decoder).join(),
          process.stderr.transform(utf8.decoder).join(),
        ]),
    ]);
    while (!done || (await sender.sealAndList()).isNotEmpty) {
      for (final name in await sender.sealAndList()) {
        final claimed = await sender.claim(name);
        if (claimed == null) continue;
        final batch = await sender.read(claimed);
        expect(batch, isNotNull);
        expect(batch!.contextJson, '{"app":"otzaria"}');
        for (final line in batch.eventLines) {
          received.add(jsonDecode(line)['n'] as int);
        }
        await sender.remove(claimed);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final codes = await finished;
    final logs = await output;
    expect(codes, [0, 0], reason: '$logs');
    expect(received, {for (var i = 0; i < 200; i++) i});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'interrupted metadata publication rebuilds from committed event files',
    () async {
      final queue = makeQueue();
      await queue.append(event(1), context);
      await File('${dir.path}/.dirty').writeAsString('');
      await File('${dir.path}/queue-state.json').writeAsString('{');
      final restarted = makeQueue();
      await restarted.append(event(2), context);
      final batches = [
        for (final name in await restarted.sealAndList())
          (await restarted.read(name))!,
      ];
      expect(
        batches.expand((b) => b.eventLines).map((l) => jsonDecode(l)['n']),
        [1, 2],
      );
    },
  );
  test('independent isolates serialize shared disk transactions', () async {
    final path = dir.path;
    await Future.wait(
      List.generate(
        8,
        (writer) => Isolate.run(() async {
          final queue = SearchFeedbackQueue(
            () async => Directory(path),
            clock: DateTime.now,
          );
          for (var i = 0; i < 20; i++) {
            await queue.append(
              {'eventId': 'iso_${writer}_$i', 'n': writer * 20 + i},
              {'app': 'otzaria'},
            );
          }
        }),
      ),
    );
    final reader = makeQueue();
    final values = <int>[];
    for (final name in await reader.sealAndList()) {
      values.addAll(
        (await reader.read(
          name,
        ))!.eventLines.map((l) => jsonDecode(l)['n'] as int),
      );
    }
    expect(values.length, 160);
    expect(values.toSet(), {for (var i = 0; i < 160; i++) i});
    expect(reader.eventCount, 160);
  });
  test('fixed clocks cannot overwrite previous segments', () async {
    final queue = SearchFeedbackQueue(
      () async => dir,
      clock: () => DateTime.utc(2026),
      segmentEvents: 1,
    );
    for (var i = 0; i < 3; i++) {
      await queue.append(event(i), context);
    }
    final names = await queue.sealAndList();
    expect(names.toSet().length, 3);
    final values = <int>[];
    for (final name in names) {
      values.addAll(
        (await queue.read(
          name,
        ))!.eventLines.map((l) => jsonDecode(l)['n'] as int),
      );
    }
    expect(values.toSet(), {0, 1, 2});
  });
  test('crash during revoke finishes purge before any restart reads', () async {
    final queue = makeQueue();
    await queue.append(event(1), context);
    final cutoff = DateTime.now().microsecondsSinceEpoch;
    await File('${dir.path}/.dirty').writeAsString('$cutoff', flush: true);
    await File(
      '${dir.path}.epoch',
    ).writeAsString('revoked:$cutoff', flush: true);
    final restarted = makeQueue();
    expect(await restarted.sealAndList(), isEmpty);
    await restarted.append(event(2), context); // stale consent cannot reopen it
    expect(await restarted.sealAndList(), isEmpty);
    await restarted.resume(); // explicit new consent
    await restarted.append(event(3), context);
    final name = (await restarted.sealAndList()).single;
    expect(
      (await restarted.read(name))!.eventLines.map((l) => jsonDecode(l)['n']),
      [3],
    );
  });
  test(
    'process death releases the OS lock without a stale lock file deadlock',
    () async {
      final process = await Process.start('dart', [
        '--packages=.dart_tool/package_config.json',
        'test/search_feedback/support/queue_writer.dart',
        dir.path,
        'lock',
      ]);
      final stderr = process.stderr.transform(utf8.decoder).join();
      expect(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'locked',
      );
      var completed = false;
      final append = makeQueue()
          .append(event(1), context)
          .then((_) => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(completed, false);
      expect(process.kill(), true);
      await process.exitCode;
      await stderr;
      await append.timeout(const Duration(seconds: 5));
      expect(completed, true);
    },
  );
}
