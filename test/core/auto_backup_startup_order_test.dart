import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String deferredAutoBackup(String source) {
    source = source.replaceAll('\r\n', '\n');
    final start = source.indexOf(
      'Future<void> _runDeferredAutoBackup() async {',
    );
    final end = source.indexOf('\n}\n', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  for (final lineEnding in {'LF': '\n', 'CRLF': '\r\n'}.entries) {
    group(lineEnding.key, () {
      final source = File('lib/main.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .replaceAll('\n', lineEnding.value);
      test('הגיבוי האוטומטי ממתין לחשיפת החלון לפני שהוא מתחיל', () {
        final body = deferredAutoBackup(source);
        const revealWait = '_mainWindowRevealedCompleter.future.timeout(';
        expect(body, contains(revealWait));
        expect(
          body.indexOf(revealWait),
          lessThan(body.indexOf('BackupService.shouldPerformAutoBackup()')),
        );
      });

      test('הגיבוי האוטומטי עדיין רץ', () {
        final body = deferredAutoBackup(source);
        expect(body, contains('await BackupService.performAutoBackup();'));
        expect(body, contains('_logNonFatalInitializationError'));
      });
    });
  }
}
