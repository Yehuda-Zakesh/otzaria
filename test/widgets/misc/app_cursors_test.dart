// מפעילים את הסשן ישירות, במקום דרך MouseTracker שמריץ אותו ב-FakeAsync.
// ignore_for_file: invalid_use_of_protected_member
@TestOn('windows')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_cursors.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      (call) async {
        calls.add(call);
        return call.method == 'createCustomCursor/windows'
            ? (call.arguments as Map)['name']
            : null;
      },
    );
  });

  tearDown(() {
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      null,
    );
  });

  List<MethodCall> named(String method) =>
      calls.where((c) => c.method == method).toList();

  test('falls back to the system hand before the cursor is created', () async {
    await AppCursors.grab.createSession(0).activate();
    expect(calls.single.method, 'activateSystemCursor');
    expect((calls.single.arguments as Map)['kind'], 'click');
  });

  testWidgets('creates the hand at the view DPR and activates it', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.5;
    await tester.runAsync(AppCursors.ensureInitialized);

    final create = named('createCustomCursor/windows').single;
    final args = create.arguments as Map;
    expect(args['width'], 27);
    expect(args['height'], 27);
    expect(args['hotX'], 13.5);
    expect((args['buffer'] as Uint8List).length, 27 * 27 * 4);

    await tester.runAsync(
      () => AppCursors.grabbing.createSession(0).activate(),
    );
    final set = named('setCustomCursor/windows').single;
    expect((set.arguments as Map)['name'], args['name']);
  });

  testWidgets('creates another cursor lazily after a DPR change', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    await tester.runAsync(() => AppCursors.grab.createSession(0).activate());

    final args = named('createCustomCursor/windows').single.arguments as Map;
    expect(args['width'], 36);
    expect(
      (named('setCustomCursor/windows').single.arguments as Map)['name'],
      args['name'],
    );

    calls.clear();
    await tester.runAsync(() => AppCursors.grab.createSession(0).activate());
    expect(named('createCustomCursor/windows'), isEmpty);
  });

  testWidgets('a session replaced before creation finishes stays silent', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    await tester.runAsync(() {
      final session = AppCursors.grab.createSession(0);
      final activation = session.activate();
      session.dispose();
      return activation;
    });
    expect(named('setCustomCursor/windows'), isEmpty);
  });
}
