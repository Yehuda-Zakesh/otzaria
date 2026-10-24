@TestOn('mac-os')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/gtk_view_window_native.dart';

void main() {
  const native = GtkViewWindowNative();
  late Directory temp;
  late Pointer<Void> Function(int) create;
  late void Function(Pointer<Void>, int) state;
  late void Function(Pointer<Void>) destroy;

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('gtk-native-test-');
    final output = '${temp.path}/libgtk_stub.dylib';
    final sdk = await Process.run('xcrun', [
      '--sdk',
      'macosx',
      '--show-sdk-path',
    ]);
    expect(sdk.exitCode, 0, reason: '${sdk.stderr}');
    final result = await Process.run('xcrun', [
      '--sdk',
      'macosx',
      'clang',
      '-dynamiclib',
      '-isysroot',
      sdk.stdout.toString().trim(),
      '-arch',
      'arm64',
      '-arch',
      'x86_64',
      'test/support/native/gtk_window_native_stub.c',
      '-o',
      output,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final path = output.toNativeUtf8();
    try {
      final load = DynamicLibrary.process()
          .lookupFunction<
            Pointer<Void> Function(Pointer<Utf8>, Int),
            Pointer<Void> Function(Pointer<Utf8>, int)
          >('dlopen');
      expect(load(path, 1 | 8), isNot(nullptr));
    } finally {
      calloc.free(path);
    }
    final lib = DynamicLibrary.open(output);
    create = lib
        .lookupFunction<
          Pointer<Void> Function(Int),
          Pointer<Void> Function(int)
        >('test_window_new');
    state = lib
        .lookupFunction<
          Void Function(Pointer<Void>, Int),
          void Function(Pointer<Void>, int)
        >('test_window_state');
    destroy = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('test_window_free');
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  test('fullscreen משמר את המסגרת הרגילה, בלי מטמון ידיות גלובלי', () {
    final window = create(0);
    addTearDown(() => destroy(window));
    expect(
      native.windowRect(window.address),
      const Rect.fromLTWH(100, 50, 800, 600),
    );
    state(window, 1 << 4);
    expect(
      native.placement(window.address)!.normal,
      const Rect.fromLTWH(100, 50, 800, 600),
    );
  });

  test('חלון שכבר ממוקסם בקריאה הראשונה משתמש בגודל הרגיל של GTK', () {
    final window = create(1 << 2);
    addTearDown(() => destroy(window));
    state(window, 1 << 2);
    expect(
      native.placement(window.address)!.normal,
      const Rect.fromLTWH(100, 50, 900, 650),
    );
  });

  test('מסגרת שהוצבה לפני maximize היא מסגרת השחזור', () {
    final window = create(0);
    addTearDown(() => destroy(window));
    const rect = Rect.fromLTWH(-1200, 80, 1000, 700);
    native.setWindowRect(window.address, rect);
    state(window, 1 << 4);
    expect(native.placement(window.address)!.normal, rect);
  });

  test('reveal מציג בפועל את החלון הנייטיבי', () async {
    final window = create(0);
    addTearDown(() => destroy(window));
    expect(native.isVisible(window.address), isFalse);
    await native.reveal(window.address);
    expect(native.isVisible(window.address), isTrue);
  });
}
