import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/printing/print_work_status.dart';

void main() {
  group('PrintWorkStatus', () {
    test('עבודות מקבילות נספרות עד שכל אחת מסתיימת', () async {
      final first = Completer<bool>();
      final second = Completer<bool>();
      final printingFirst = PrintWorkStatus.track(() => first.future);
      final printingSecond = PrintWorkStatus.track(() => second.future);
      expect(PrintWorkStatus.hasActiveJobs, isTrue);
      first.complete(false);
      expect(await printingFirst, isFalse);
      expect(PrintWorkStatus.hasActiveJobs, isTrue);
      second.complete(true);
      expect(await printingSecond, isTrue);
      expect(PrintWorkStatus.hasActiveJobs, isFalse);
    });

    test('כשל משחרר את המעקב ומעביר את החריגה המקורית', () async {
      final error = StateError('spooler');
      await expectLater(
        PrintWorkStatus.track(() => Future.error(error)),
        throwsA(same(error)),
      );
      expect(PrintWorkStatus.hasActiveJobs, isFalse);
    });

    test('גם כשל סינכרוני משחרר את המעקב', () async {
      await expectLater(
        PrintWorkStatus.track(() => throw StateError('driver')),
        throwsStateError,
      );
      expect(PrintWorkStatus.hasActiveJobs, isFalse);
    });
  });

  group('confirmCloseWhilePrinting', () {
    Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    testWidgets('בלי הדפסה פעילה — מאשר בלי דיאלוג', (tester) async {
      await pumpApp(tester);
      expect(await confirmCloseWhilePrinting(), isTrue);
      expect(find.text(PdfMessages.closeWhilePrinting), findsNothing);
    });

    for (final confirm in [true, false]) {
      testWidgets('בהדפסה פעילה — שואל, ומחזיר את הבחירה ($confirm)', (
        tester,
      ) async {
        await pumpApp(tester);
        final job = Completer<bool>();
        final printing = PrintWorkStatus.track(() => job.future);
        try {
          final result = confirmCloseWhilePrinting();
          await tester.pumpAndSettle();
          expect(find.text(PdfMessages.closeWhilePrinting), findsOneWidget);
          await tester.tap(
            find.text(
              confirm ? PdfMessages.closeWhilePrintingConfirm : 'ביטול',
            ),
          );
          await tester.pumpAndSettle();
          expect(await result, confirm);
        } finally {
          job.complete(false);
          await printing;
        }
      });
    }
  });
}
