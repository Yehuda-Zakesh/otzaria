import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Disposes [document] once the work the viewer started on it has finished.
///
/// pdfrx releases each use of a document on a microtask of the zone that
/// started it, so under FakeAsync dispose waits until the test pumps.
Future<void> disposePdfDocument(
  WidgetTester tester,
  PdfDocument document,
) async {
  var disposed = false;
  unawaited(document.dispose().whenComplete(() => disposed = true));
  for (var i = 0; i < 200 && !disposed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(disposed, isTrue, reason: 'PdfDocument.dispose did not complete');
}
