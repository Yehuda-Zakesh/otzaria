import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/android_anr_source.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

const _javaBlockedTrace = '''
"main" prio=5 tid=1 Blocked
  | group="main" sCount=1 ucsCount=0 flags=1 obj=0x72a5e1b8 self=0xb400007d1c8e4c00
  | sysTid=12345 nice=-10 cgrp=top-app sched=0/0 handle=0x7e3b0f54f8
  at org.otzaria.otzaria.FolderImportChannel.copyTree(FolderImportChannel.kt:301)
  - waiting to lock <0x0b1c2d3e> (a java.lang.Object) held by thread 23
  at org.otzaria.otzaria.FolderImportChannel.onMethodCall(FolderImportChannel.kt:120)
  at io.flutter.plugin.common.MethodChannel\$IncomingMethodCallHandler.onMessage(MethodChannel.java:267)
  at io.flutter.embedding.engine.dart.DartMessenger.invokeHandler(DartMessenger.java:292)
  at android.os.Handler.handleCallback(Handler.java:942)
  at android.os.Looper.loopOnce(Looper.java:201)
  at android.os.Looper.loop(Looper.java:288)
  at android.app.ActivityThread.main(ActivityThread.java:7872)
  at java.lang.reflect.Method.invoke(Native method)
  at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:936)
''';

const _nativeFlutterTrace = '''
"main" prio=5 tid=1 Runnable
  | group="main" sCount=0 ucsCount=0 flags=0 obj=0x72a5e1b8 self=0xb400007d1c8e4c00
  native: #00 pc 000000000009c1e4  /apex/com.android.runtime/lib64/bionic/libc.so (__futex_wait+4) (BuildId: 2f1a)
  native: #01 pc 00000000012a3f40  /data/app/~~abc==/org.otzaria-xyz==/lib/arm64/libapp.so (BuildId: 77aa)
  native: #02 pc 0x0000000001b00010  /data/app/~~abc==/org.otzaria-xyz==/base.apk!libflutter.so (offset 0x1000) (flutter::Shell::OnPlatformViewDispatchPlatformMessage(int)+120) (BuildId: 88bb)
  native: #03 pc 00000000012a3f88  /data/app/~~abc==/org.otzaria-xyz==/lib/arm64/libapp.so (BuildId: 77aa)
  at io.flutter.embedding.engine.FlutterJNI.nativeDispatch(Native method)
  at android.os.Looper.loop(Looper.java:288)
''';

const _idleMainTrace = '''
"main" prio=5 tid=1 Native
  native: #00 pc 000000000009c1e4  /apex/com.android.runtime/lib64/bionic/libc.so (__epoll_pwait+4)
  native: #01 pc 0000000000010b4c  /system/lib64/libutils.so (android::Looper::pollOnce(int, int*, int*, void**)+156)
  at android.os.MessageQueue.nativePollOnce(Native method)
  at android.os.MessageQueue.next(MessageQueue.java:335)
  at android.os.Looper.loop(Looper.java:288)
''';

void main() {
  group('anrSignatureFromTrace', () {
    test('Java blocked main thread prefers app frames', () {
      final sig = anrSignatureFromTrace(_javaBlockedTrace);
      expect(sig.exceptionType, 'ANR');
      expect(sig.frames, [
        'org.otzaria.otzaria.FolderImportChannel.copyTree',
        'org.otzaria.otzaria.FolderImportChannel.onMethodCall',
        r'io.flutter.plugin.common.MethodChannel$IncomingMethodCallHandler.onMessage',
      ]);
    });

    test('native libapp/libflutter frames normalized', () {
      final sig = anrSignatureFromTrace(_nativeFlutterTrace);
      expect(sig.frames, [
        'libapp.so+0x12a3f40',
        'libflutter.so flutter::Shell::OnPlatformViewDispatchPlatformMessage(int)',
        'libapp.so+0x12a3f88',
      ]);
    });

    test('only framework frames: skips generic ones', () {
      final sig = anrSignatureFromTrace(_idleMainTrace);
      expect(sig.frames, [
        'libutils.so android::Looper::pollOnce(int, int*, int*, void**)',
        'android.os.MessageQueue.next',
      ]);
    });

    test('stops at the end of the main section', () {
      const trace =
          '----- pid 1 -----\n'
          '"main" prio=5 tid=1 Blocked\n'
          '  at android.os.MessageQueue.next(MessageQueue.java:335)\n'
          '\n'
          '"worker" prio=5 tid=2 Runnable\n'
          '  at org.otzaria.Worker.run(Worker.java:1)\n';
      expect(anrSignatureFromTrace(trace).frames, [
        'android.os.MessageQueue.next',
      ]);
    });

    test('null/empty trace → ANR without frames', () {
      for (final trace in [null, '', '   \n']) {
        final sig = anrSignatureFromTrace(trace);
        expect(sig, const CrashSignature(exceptionType: 'ANR', frames: []));
      }
    });

    test('frames are clamped to the contract limit', () {
      final long = 'org.otzaria.${'a' * 400}';
      final sig = anrSignatureFromTrace('  at $long(X.java:1)\n');
      expect(sig.frames.single.length, CrashSignature.maxFrameLength);
    });
  });

  test('anrDetails fits the limit and keeps the header', () {
    final details = anrDetails(
      timestamp: DateTime.utc(2026, 10, 18, 9),
      description: 'Input dispatching timed out',
      importance: 100,
      mainThreadTrace: 'x' * 20000,
    );
    expect(details.length, AndroidAnrSource.maxDetailsLength);
    expect(details, contains('Description: Input dispatching timed out'));
    expect(details, contains('Main thread:\n'));
    expect(details, endsWith('(truncated)'));
  });

  group('AndroidAnrSource.takeNewAnr', () {
    late Directory dir;
    late String statePath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('anr_source_test');
      statePath = p.join(dir.path, AndroidAnrSource.stateFileName);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Map<String, Object?> exit(int ts, {String? trace}) => {
      'timestamp': ts,
      'pid': 42,
      'description': 'anr $ts',
      'importance': 100,
      'processName': 'org.otzaria',
      'mainThreadTrace': trace,
    };

    AndroidAnrSource source(
      List<Map<String, Object?>> Function() exits, {
      List<int>? calls,
      bool isAndroid = true,
    }) => AndroidAnrSource(
      stateFilePath: statePath,
      isAndroid: isAndroid,
      clock: () => DateTime.fromMillisecondsSinceEpoch(5000),
      invoker: (sinceMs) async {
        calls?.add(sinceMs);
        final all = exits();
        return {
          'exits': all.where((e) => (e['timestamp'] as int) > sinceMs).toList(),
          'newestAnyTimestamp': all.isEmpty ? null : all.first['timestamp'],
        };
      },
    );

    int watermark() =>
        (jsonDecode(File(statePath).readAsStringSync()) as Map)['lastTimestamp']
            as int;

    test('first run stores the watermark and reports nothing', () async {
      final calls = <int>[];
      final anr = await source(
        () => [exit(3000), exit(1000)],
        calls: calls,
      ).takeNewAnr();
      expect(anr, isNull);
      expect(watermark(), 3000);
      expect(calls, [5000]);
    });

    test('first run without any exit uses the clock', () async {
      expect(await source(() => []).takeNewAnr(), isNull);
      expect(watermark(), 5000);
    });

    test('a new ANR is returned once; older unseen ones are skipped', () async {
      File(statePath).writeAsStringSync('{"lastTimestamp":1000}');
      var exits = [exit(4000, trace: _javaBlockedTrace), exit(2000)];
      final s = source(() => exits);

      final anr = await s.takeNewAnr();
      expect(anr, isNotNull);
      expect(anr!.timestamp, DateTime.fromMillisecondsSinceEpoch(4000));
      expect(anr.description, 'anr 4000');
      expect(anr.signature, anrSignatureFromTrace(_javaBlockedTrace));
      expect(anr.details, contains('FolderImportChannel.copyTree'));
      expect(watermark(), 4000);

      expect(await s.takeNewAnr(), isNull);

      exits = [exit(6000), ...exits];
      expect((await s.takeNewAnr())!.timestamp.millisecondsSinceEpoch, 6000);
    });

    test('background ANRs are skipped but still marked seen', () async {
      File(statePath).writeAsStringSync('{"lastTimestamp":1000}');
      Map<String, Object?> withImportance(int ts, int importance) =>
          exit(ts)..['importance'] = importance;
      var exits = [withImportance(5000, 400), withImportance(3000, 200)];
      final s = source(() => exits);

      final anr = await s.takeNewAnr();
      expect(anr!.timestamp.millisecondsSinceEpoch, 3000);
      expect(watermark(), 5000);

      exits = [withImportance(7000, 300), ...exits];
      expect(await s.takeNewAnr(), isNull);
      expect(watermark(), 7000);
    });

    test('not Android → null without touching the channel', () async {
      final calls = <int>[];
      final s = source(() => [exit(1)], calls: calls, isAndroid: false);
      expect(await s.takeNewAnr(), isNull);
      expect(calls, isEmpty);
      expect(File(statePath).existsSync(), isFalse);
    });

    test('channel errors and malformed replies → null', () async {
      File(statePath).writeAsStringSync('{"lastTimestamp":1000}');
      final throwing = AndroidAnrSource(
        stateFilePath: statePath,
        isAndroid: true,
        invoker: (_) async => throw Exception('boom'),
      );
      expect(await throwing.takeNewAnr(), isNull);

      for (final reply in <Object?>[
        null,
        'x',
        {'exits': 'nope'},
        {
          'exits': [
            'x',
            {'timestamp': 'y'},
          ],
        },
      ]) {
        final s = AndroidAnrSource(
          stateFilePath: statePath,
          isAndroid: true,
          invoker: (_) async => reply,
        );
        expect(await s.takeNewAnr(), isNull);
      }
      expect(watermark(), 1000);
    });

    test('corrupt state file is treated as a first run', () async {
      File(statePath).writeAsStringSync('{not json');
      expect(await source(() => [exit(3000)]).takeNewAnr(), isNull);
      expect(watermark(), 3000);
    });

    test('unwritable state → null rather than a repeating report', () async {
      // נתיב שהורה שלו הוא קובץ — הכתיבה נכשלת.
      File(p.join(dir.path, 'blocker')).writeAsStringSync('');
      final s = AndroidAnrSource(
        stateFilePath: p.join(dir.path, 'blocker', 'state.json'),
        isAndroid: true,
        invoker: (_) async => {
          'exits': [exit(9000)],
        },
      );
      expect(await s.takeNewAnr(), isNull);
    });
  });
}
