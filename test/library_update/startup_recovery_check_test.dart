import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/library_update/services/startup_recovery_check.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// recovery שמדמה סימון שלא ניתן למחיקה (ProgramData ללא הרשאת כתיבה).
class _UndeletableMarkerRecovery extends LibraryDbRecoveryService {
  const _UndeletableMarkerRecovery();

  @override
  void clearStaleArtifacts(String dbPath) {
    // המחיקה "נכשלת" בשקט — כמו _deleteQuietly על קובץ ללא הרשאה.
  }
}

void main() {
  late Directory tmp;
  late String dbPath;
  late Map<String, String> prefs;
  late List<String> loggedTitles;
  late int quickCheckRuns;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('recovery_check');
    dbPath = '${tmp.path}/seforim.db';
    File(dbPath).writeAsStringSync('fake-db');
    prefs = {};
    loggedTitles = [];
    quickCheckRuns = 0;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void writeMarker() {
    File('$dbPath.applying').writeAsStringSync(
      jsonEncode({'fromVersion': 6, 'toVersion': 7, 'timestamp': 't1'}),
      flush: true,
    );
  }

  StartupRecoveryCheck buildCheck({
    required bool quickCheckResult,
    LibraryDbRecoveryService recovery = const LibraryDbRecoveryService(),
  }) {
    return StartupRecoveryCheck(
      recovery: recovery,
      runQuickCheck: (path) async {
        quickCheckRuns++;
        return quickCheckResult;
      },
      readPref: (key) => prefs[key],
      writePref: (key, value) async => prefs[key] = value,
      logError: (title, message) => loggedTitles.add(title),
    );
  }

  Future<void> runAndVerify(StartupRecoveryCheck check) async {
    await check.run(dbPath);
    await check.verifyPending();
  }

  test(
    'סימון ללא גיבוי — run מסתיים בלי quick_check; הסריקה רק ב-verifyPending',
    () async {
      writeMarker();
      final check = buildCheck(quickCheckResult: true);
      await check.run(dbPath);
      expect(quickCheckRuns, 0);
      expect(check.hasPendingVerification, isTrue);
      expect(File('$dbPath.applying').existsSync(), isTrue);

      await check.verifyPending();
      expect(quickCheckRuns, 1);
      expect(check.hasPendingVerification, isFalse);
      expect(File('$dbPath.applying').existsSync(), isFalse);

      // קריאה חוזרת אינה סורקת שוב.
      await check.verifyPending();
      expect(quickCheckRuns, 1);
    },
  );

  test('ללא סימון — אין quick_check ואין רישום', () async {
    await runAndVerify(buildCheck(quickCheckResult: true));
    expect(quickCheckRuns, 0);
    expect(loggedTitles, isEmpty);
    expect(prefs, isEmpty);
  });

  test('סימון + quick_check עובר → הסימון נמחק, בלי העדפה ובלי לוג', () async {
    writeMarker();
    await runAndVerify(buildCheck(quickCheckResult: true));
    expect(quickCheckRuns, 1);
    expect(File('$dbPath.applying').existsSync(), isFalse);
    expect(prefs, isEmpty);
    expect(loggedTitles, isEmpty);
  });

  test('סימון שאינו ניתן למחיקה — הסריקה רצה פעם אחת בלבד', () async {
    writeMarker();
    const recovery = _UndeletableMarkerRecovery();

    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 1);
    expect(File('$dbPath.applying').existsSync(), isTrue);
    expect(prefs[StartupRecoveryCheck.prefKey], startsWith('ok|'));
    expect(loggedTitles, ['Library update marker cleanup failed']);

    // "עלייה" שנייה עם אותו סימון: בלי סריקה חוזרת ובלי לוג נוסף.
    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 1);
    expect(loggedTitles, hasLength(1));
  });

  test('DB פגום — נסרק פעם אחת, נרשם לוג, ולא נסרק שוב', () async {
    writeMarker();

    await runAndVerify(buildCheck(quickCheckResult: false));
    expect(quickCheckRuns, 1);
    expect(File('$dbPath.applying').existsSync(), isTrue);
    expect(prefs[StartupRecoveryCheck.prefKey], startsWith('corrupt|'));
    expect(loggedTitles, [
      'Library DB failed quick_check after interrupted update',
    ]);

    await runAndVerify(buildCheck(quickCheckResult: false));
    expect(quickCheckRuns, 1);
    expect(loggedTitles, hasLength(1));
  });

  test('סימון חדש (עדכון אחר) מפקיע תוצאה שמורה — הסריקה רצה שוב', () async {
    writeMarker();
    const recovery = _UndeletableMarkerRecovery();
    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 1);

    // עדכון חדש כותב סימון עם תוכן אחר.
    File('$dbPath.applying').writeAsStringSync(
      jsonEncode({'fromVersion': 7, 'toVersion': 8, 'timestamp': 't2'}),
      flush: true,
    );
    await runAndVerify(buildCheck(quickCheckResult: true, recovery: recovery));
    expect(quickCheckRuns, 2);
  });

  test('סימון + גיבוי → שחזור מהגיבוי בלי quick_check', () async {
    writeMarker();
    File('$dbPath.backup').writeAsStringSync('fake-db');

    await runAndVerify(buildCheck(quickCheckResult: true));
    expect(quickCheckRuns, 0);
    expect(File('$dbPath.applying').existsSync(), isFalse);
    expect(File('$dbPath.backup').existsSync(), isFalse);
    expect(File(dbPath).readAsStringSync(), 'fake-db');
  });

  test(
    'שחזור בעלייה אינו משנה קובצי .old או sidecars ללא בעלות ידועה',
    () async {
      for (final emptyMain in [false, true]) {
        if (File(dbPath).existsSync()) File(dbPath).deleteSync();
        if (emptyMain) File(dbPath).writeAsStringSync('');
        File('$dbPath.old').writeAsStringSync('retired-db');
        for (final suffix in ['-wal', '-shm', '-journal']) {
          File('$dbPath$suffix').writeAsStringSync('preserve$suffix');
        }

        await buildCheck(quickCheckResult: true).run(dbPath);

        expect(File(dbPath).existsSync(), emptyMain);
        if (emptyMain) expect(File(dbPath).lengthSync(), 0);
        expect(File('$dbPath.old').readAsStringSync(), 'retired-db');
        for (final suffix in ['-wal', '-shm', '-journal']) {
          expect(File('$dbPath$suffix').readAsStringSync(), 'preserve$suffix');
        }
      }
    },
  );
  for (final emptyMain in [false, true]) {
    test('WAL שמור של .old נשמר כשמסד ${emptyMain ? 'ריק' : 'חסר'}', () async {
      final sourcePath = '${tmp.path}/source.db';
      final source = sqlite3.open(sourcePath);
      try {
        source.execute('PRAGMA journal_mode=WAL');
        source.execute('CREATE TABLE books (id INTEGER PRIMARY KEY)');
        source.execute('INSERT INTO books VALUES (1)');
        source.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        source.execute('INSERT INTO books VALUES (2)');
        File(sourcePath).copySync('$dbPath.old');
        for (final suffix in ['-wal', '-shm']) {
          File('$sourcePath$suffix').copySync('$dbPath$suffix');
        }
      } finally {
        source.close();
      }
      File(dbPath).deleteSync();
      if (emptyMain) File(dbPath).writeAsStringSync('');
      final wal = File('$dbPath-wal').readAsBytesSync();

      await buildCheck(quickCheckResult: true).run(dbPath);

      expect(File('$dbPath-wal').readAsBytesSync(), wal);
      expect(File('$dbPath.old').existsSync(), isTrue);
      if (emptyMain) File(dbPath).deleteSync();
      File('$dbPath.old').renameSync(dbPath);
      final restored = sqlite3.open(dbPath);
      try {
        expect(restored.select('SELECT id FROM books').map((r) => r['id']), [
          1,
          2,
        ]);
      } finally {
        restored.close();
      }
    });
  }
}
