import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/host_relay.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';

import '../../test_helpers/fake_host_window.dart';

const _namespace = 'otzaria.test.hostrelay';

void main() {
  tearDown(() {
    WindowRole.isSecondary = false;
    WindowBus.namespace = 'otzaria.window';
  });

  test('בלי מארח הבקשה אינה נמסרת', () async {
    WindowBus.namespace = _namespace;
    final response = await HostRelay.sendToHost('x');
    expect(response.delivered, isFalse);
  });

  test('הבקשה מגיעה למארח עם הסוג והפרמטרים, ותשובתו חוזרת', () async {
    final host = FakeHostWindow(
      namespace: _namespace,
      respond: (request) => {'echo': request['value']},
    )..register();
    addTearDown(host.dispose);

    final response = await HostRelay.sendToHost('x', args: {'value': 7});

    expect(response.delivered, isTrue);
    expect(response.result, {'echo': 7});
    expect(host.ofType('x').single['value'], 7);
    expect(await HostRelay.fetchHostSnapshot('x'), {'echo': null});
  });

  group('HostStateBroadcaster', () {
    late ReceivePort peer;
    late List<Map<String, dynamic>> received;

    setUp(() {
      WindowBus.namespace = _namespace;
      WindowBus.instance.register();
      received = [];
      peer = ReceivePort();
      // משבצת 2: החלון האחר. המארח עצמו תפס את משבצת 1.
      IsolateNameServer.registerPortWithName(peer.sendPort, '$_namespace.2');
      peer.listen((message) {
        final map = message as Map;
        received.add(Map<String, dynamic>.from(map['body'] as Map));
        (map['reply'] as SendPort).send({'ok': true, 'result': true});
      });
    });

    tearDown(() {
      IsolateNameServer.removePortNameMapping('$_namespace.2');
      peer.close();
      WindowBus.instance.unregister();
    });

    test('עדכונים צפופים מתלכדים לשידור אחד עם המצב האחרון', () async {
      var value = 0;
      final broadcaster = HostStateBroadcaster(
        'state',
        () => {'value': value},
        interval: const Duration(milliseconds: 20),
      );
      for (value = 1; value <= 3; value++) {
        broadcaster.changed();
      }
      value = 3;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(received, [
        {
          'type': 'state',
          'state': {'value': 3},
        },
      ]);
    });

    test('חלון משני אינו משדר', () async {
      WindowRole.isSecondary = true;
      HostStateBroadcaster(
        'state',
        () => const {},
        interval: const Duration(milliseconds: 1),
      ).changed();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    });
  });
}
