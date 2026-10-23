import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/external_activation_service.dart';
import 'package:otzaria/core/external_activation_channel.dart';
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:path/path.dart' as p;

const _a = 'otzaria://library/reindex?n=1';
const _b = 'otzaria://library/reindex?n=2';
const _c = 'otzaria://library/reindex?n=3';
const _newWindow = 'otzaria://window/new';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ExternalActivationQueue queue;
  late List<String> delivered;
  late List<(int, Map<String, dynamic>)> forwarded;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ext_activation_svc_');
    queue = ExternalActivationQueue(
      queueFilePath: p.join(tempDir.path, 'pending.jsonl'),
    );
    delivered = [];
    forwarded = [];
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<bool> handler(String uri) async {
    delivered.add(uri);
    return true;
  }

  ExternalActivationService service({
    bool canOpenWindows = true,
    int? lastActive,
    int? ownSlot = 0,
    Object? forwardResult = true,
    Future<int?> Function()? lastActiveSlot,
    ExternalActivationChannel? channel,
    Stream<FileSystemEvent> Function(Directory)? watchDirectory,
    bool multiView = false,
    AppWindowId lastActiveWindow = AppWindowId.primary,
  }) => ExternalActivationService(
    queue: queue,
    channel: channel,
    canOpenWindows: () => canOpenWindows,
    lastActiveSlot: lastActiveSlot ?? () async => lastActive,
    ownSlot: () => ownSlot,
    forward: (slot, body) async {
      forwarded.add((slot, body));
      return forwardResult;
    },
    watchDirectory: watchDirectory,
    multiView: () => multiView,
    lastActiveWindow: () => lastActiveWindow,
  );

  group('drain', () {
    test('delivers queued URIs in order, once', () async {
      for (final uri in [_a, _b, _c]) {
        await queue.enqueueUriString(uri);
      }
      final svc = service(canOpenWindows: false)..attachWindow(handler);

      await svc.processPending();
      await svc.processPending();

      expect(delivered, [_a, _b, _c]);
      expect(forwarded, isEmpty);
    });

    test('concurrent triggers coalesce without double delivery', () async {
      await queue.enqueueUriString(_a);
      final svc = service(canOpenWindows: false)..attachWindow(handler);

      final first = svc.processPending();
      await queue.enqueueUriString(_b);
      final second = svc.processPending();
      await Future.wait([first, second]);

      expect(delivered, [_a, _b]);
    });

    test('leaves the queue untouched while no window is attached', () async {
      await queue.enqueueUriString(_a);
      final svc = service(canOpenWindows: false);

      await svc.processPending();
      expect(delivered, isEmpty);

      svc.attachWindow(handler);
      await svc.processPending();
      expect(delivered, [_a]);
    });
  });

  group('routing', () {
    test('forwards to the last-active peer window over the bus', () async {
      await queue.enqueueUriString(_a);
      await queue.enqueueUriString(_b);
      final svc = service(lastActive: 2)..attachWindow(handler);

      await svc.processPending();

      expect(delivered, isEmpty);
      expect(forwarded.map((f) => f.$1), [2, 2]);
      expect(forwarded.map((f) => f.$2), [
        {'type': MultiWindowService.requestOpenUri, 'uri': _a},
        {'type': MultiWindowService.requestOpenUri, 'uri': _b},
      ]);
    });

    test('opens here when the peer does not handle it', () async {
      await queue.enqueueUriString(_a);
      final svc = service(lastActive: 2, forwardResult: null)
        ..attachWindow(handler);

      await svc.processPending();

      expect(forwarded.single.$1, 2);
      expect(delivered, [_a]);
    });

    test('opens here when this window or none was last active', () async {
      await queue.enqueueUriString(_a);
      final own = service(lastActive: 0)..attachWindow(handler);
      await own.processPending();

      await queue.enqueueUriString(_b);
      final none = service(lastActive: null)..attachWindow(handler);
      await none.processPending();

      expect(delivered, [_a, _b]);
      expect(forwarded, isEmpty);
    });

    test('a new-window link opens here without asking for a target', () async {
      await queue.enqueueUriString(_newWindow);
      var asked = false;
      final svc = service(
        lastActiveSlot: () async {
          asked = true;
          return 2;
        },
      )..attachWindow(handler);

      await svc.processPending();

      expect(asked, isFalse);
      expect(delivered, [_newWindow]);
    });

    test('drops a URI when the window detaches mid-route', () async {
      await queue.enqueueUriString(_a);
      final target = Completer<int?>();
      final svc = service(lastActiveSlot: () => target.future)
        ..attachWindow(handler);

      final drain = svc.processPending();
      await pumpEventQueue();
      svc.detachWindow(handler);
      target.complete(2);
      await drain;

      expect(delivered, isEmpty);
      expect(forwarded, isEmpty);
    });
  });

  test('start delivers platform URIs, then drains on queue events', () async {
    const channel = MethodChannel('test/external_activation_service');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == ExternalActivationChannel.getPendingUriStringsMethod) {
        return [_a];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final events = StreamController<FileSystemEvent>();
    addTearDown(events.close);
    await queue.enqueueUriString(_b);

    final svc = service(
      canOpenWindows: false,
      channel: ExternalActivationChannel(channel: channel),
      watchDirectory: (_) => events.stream,
    )..attachWindow(handler);
    addTearDown(svc.dispose);

    await svc.start();
    expect(delivered, [_a, _b]);

    await queue.enqueueUriString(_c);
    events.add(
      FileSystemModifyEvent(p.join(tempDir.path, 'other'), false, true),
    );
    await pumpEventQueue();
    expect(delivered, [_a, _b]);

    events.add(
      FileSystemModifyEvent(p.join(tempDir.path, 'pending.jsonl'), false, true),
    );
    await pumpEventQueue();
    await svc.processPending();
    expect(delivered, [_a, _b, _c]);
  });

  group('Dart windows in one isolate', () {
    const viewA = AppWindowId('window-view-2');
    const viewB = AppWindowId('window-view-3');
    late List<(AppWindowId, String)> viewDelivered;
    late Map<AppWindowId, bool> visible;
    late Map<AppWindowId, ExternalUriHandler> viewHandlers;
    var mainVisible = true;

    setUp(() {
      viewDelivered = [];
      visible = {viewA: true, viewB: true};
      viewHandlers = {
        for (final id in [viewA, viewB])
          id: (uri) async {
            viewDelivered.add((id, uri));
            return true;
          },
      };
      mainVisible = true;
    });

    ExternalActivationService hybrid(AppWindowId lastActive) {
      final svc = service(multiView: true, lastActiveWindow: lastActive)
        ..attachWindow(handler, isVisible: () async => mainVisible);
      for (final id in [viewA, viewB]) {
        svc.attachViewWindow(
          id,
          viewHandlers[id]!,
          isVisible: () async => visible[id]!,
        );
      }
      return svc;
    }

    test('the last active Dart window gets the link, not the runner', () async {
      await queue.enqueueUriString(_a);
      await hybrid(viewA).processPending();

      expect(viewDelivered, [(viewA, _a)]);
      expect(delivered, isEmpty);
      expect(forwarded, isEmpty);
    });

    test('main last active and visible keeps the link', () async {
      await queue.enqueueUriString(_a);
      await hybrid(AppWindowId.primary).processPending();

      expect(delivered, [_a]);
      expect(viewDelivered, isEmpty);
    });

    test(
      'a hidden main is not raised while a Dart window is visible',
      () async {
        mainVisible = false;
        visible[viewB] = false;
        await queue.enqueueUriString(_a);
        await hybrid(AppWindowId.primary).processPending();

        expect(viewDelivered, [(viewA, _a)]);
        expect(delivered, isEmpty);
      },
    );

    test('with nothing visible main shows itself', () async {
      mainVisible = false;
      visible
        ..[viewA] = false
        ..[viewB] = false;
      await queue.enqueueUriString(_a);
      await hybrid(viewA).processPending();

      expect(delivered, [_a]);
      expect(viewDelivered, isEmpty);
    });

    test('a detached window no longer receives links', () async {
      final svc = hybrid(viewA);
      // ביטול עם handler אחר (חלון שנבנה מחדש) אינו מסיר את הרשום.
      svc.detachViewWindow(viewA, handler);
      await queue.enqueueUriString(_a);
      await svc.processPending();
      expect(viewDelivered, [(viewA, _a)]);

      svc.detachViewWindow(viewA, viewHandlers[viewA]!);
      await queue.enqueueUriString(_b);
      await svc.processPending();
      expect(delivered, [_b]);
    });

    test('"new window" is handled by main', () async {
      await queue.enqueueUriString(_newWindow);
      await hybrid(viewA).processPending();

      expect(delivered, [_newWindow]);
      expect(viewDelivered, isEmpty);
    });
  });
}
