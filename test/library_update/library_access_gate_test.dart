import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:path/path.dart' as p;

LibraryAccessGate _gate({
  List<String>? log,
  LibraryAccessRoutine? selfAccess,
  bool renameProbe = false,
}) => LibraryAccessGate(
  selfAccess:
      selfAccess ??
      LibraryAccessRoutine(suspend: () async {}, resume: (_) async {}),
  renameProbe: renameProbe,
  logError: (title, error, _) => log?.add('$title: $error'),
);

void main() {
  test('החלפה שנייה בזמן שהראשונה רצה נכשלת בלי לסגור את המסד', () async {
    final self = <String>[];
    final gate = _gate(
      selfAccess: LibraryAccessRoutine(
        suspend: () async => self.add('suspend'),
        resume: (dbReplaced) async => self.add('resume:$dbReplaced'),
      ),
    );
    final first = Completer<void>();
    final running = gate.runExclusive<void>(
      dbPath: 'missing.db',
      body: (_) => first.future,
    );
    await pumpEventQueue();
    expect(gate.isSuspending, isTrue);

    await expectLater(
      gate.runExclusive<void>(dbPath: 'missing.db', body: (_) async {}),
      throwsA(isA<LibrarySuspendFailed>()),
    );
    expect(self, ['suspend']);

    first.complete();
    await running;
    expect(self, ['suspend', 'resume:false']);
    expect(gate.isSuspending, isFalse);
  });

  test('resumeAll אידמפוטנטי ומשחרר להחלפה הבאה', () async {
    final gate = _gate();
    final suspension = await gate.suspendAll();
    await expectLater(gate.suspendAll(), throwsA(isA<LibrarySuspendFailed>()));
    await gate.resumeAll(suspension, dbReplaced: false);
    await gate.resumeAll(suspension, dbReplaced: false);
    expect(gate.isSuspending, isFalse);
    await gate.resumeAll(await gate.suspendAll(), dbReplaced: true);
  });

  group('runExclusive', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('gate_test_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('סוגר ומחדש את המסד, עם התוצאה', () async {
      final self = <String>[];
      final gate = _gate(
        renameProbe: true,
        selfAccess: LibraryAccessRoutine(
          suspend: () async => self.add('suspend'),
          resume: (dbReplaced) async => self.add('resume:$dbReplaced'),
        ),
      );
      final dbPath = p.join(temp.path, 'seforim.db');
      File(dbPath).writeAsStringSync('db');

      final result = await gate.runExclusive(
        dbPath: dbPath,
        body: (scope) async {
          expect(self, ['suspend']);
          scope.markDbReplaced();
          return 7;
        },
      );
      expect(result, 7);
      expect(self, ['suspend', 'resume:true']);
      expect(gate.isSuspending, isFalse);
      expect(File(dbPath).readAsStringSync(), 'db');
      expect(File('$dbPath.release-probe').existsSync(), isFalse);
    });

    test('כשל ב-body מחדש בלי דגל החלפה', () async {
      final self = <String>[];
      final gate = _gate(
        selfAccess: LibraryAccessRoutine(
          suspend: () async => self.add('suspend'),
          resume: (dbReplaced) async => self.add('resume:$dbReplaced'),
        ),
      );
      await expectLater(
        gate.runExclusive<void>(
          dbPath: p.join(temp.path, 'missing.db'),
          body: (_) async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      expect(self, ['suspend', 'resume:false']);
      expect(gate.isSuspending, isFalse);
    });

    test('כשל בסגירה משחרר את השער', () async {
      final gate = _gate(
        selfAccess: LibraryAccessRoutine(
          suspend: () async => throw StateError('worker stuck'),
          resume: (_) async {},
        ),
      );
      await expectLater(
        gate.runExclusive<void>(dbPath: 'missing.db', body: (_) async {}),
        throwsStateError,
      );
      expect(gate.isSuspending, isFalse);
    });

    test(
      'מסד שעדיין פתוח בתהליך: body לא רץ והמסד נפתח מחדש',
      () async {
        final self = <String>[];
        final log = <String>[];
        final dbPath = p.join(temp.path, 'seforim.db');
        final db = sqlite3.sqlite3.open(dbPath)..execute('CREATE TABLE t(x)');
        addTearDown(db.close);
        final gate = _gate(
          renameProbe: true,
          log: log,
          selfAccess: LibraryAccessRoutine(
            suspend: () async => self.add('suspend'),
            resume: (dbReplaced) async => self.add('resume:$dbReplaced'),
          ),
        );
        var ran = false;
        await expectLater(
          gate.runExclusive(dbPath: dbPath, body: (_) async => ran = true),
          throwsA(isA<LibraryStillOpenException>()),
        );
        expect(ran, isFalse);
        expect(self, ['suspend', 'resume:false']);
        expect(log.single, contains('rename probe'));
        expect(File(dbPath).existsSync(), isTrue);
      },
      skip: !Platform.isWindows,
    );
  });
}
