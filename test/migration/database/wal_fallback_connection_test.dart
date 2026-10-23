import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

import '../../support/sqlite_shm_failure.dart';

void main() {
  late Directory dir;
  late SqliteShmFailure failure;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wal_fallback_connection');
    path = p.join(dir.path, 'cache.db');
    sqlite3.version;
    failure = SqliteShmFailure();
  });
  tearDown(() {
    failure.dispose();
    dir.deleteSync(recursive: true);
  });

  test('כשל בהמרה בזמן כתיבה אינו משאיר חיבור נועל בלעדית', () {
    final writer = openWritableDatabase(path, 'writer');
    addTearDown(writer.close);
    writer.execute('CREATE TABLE t(x)');
    writer.execute('INSERT INTO t VALUES(1)');
    writer.execute('BEGIN IMMEDIATE');
    failure.errorCode = SqlExtendedError.SQLITE_IOERR_SHMOPEN;

    final db = openWritableDatabase(path, 'reopened', busyTimeoutMs: 20);
    addTearDown(db.close);
    expect(db.select('PRAGMA busy_timeout').first.values.first, 20);

    failure.errorCode = 0;
    writer.execute('ROLLBACK');
    db.execute('INSERT INTO t VALUES(2)');
    final reader = sqlite3.open(path)..execute('PRAGMA busy_timeout=20');
    addTearDown(reader.close);
    expect(reader.select('SELECT count(*) FROM t').first.values.first, 2);
    expect(db.select('PRAGMA locking_mode').first.values.first, 'normal');
  });

  for (final reopen in [2, 3]) {
    test('כשל בפתיחה מחדש ($reopen) אינו משאיר חיבור פתוח', () {
      final writer = openWritableDatabase(path, 'writer');
      addTearDown(writer.close);
      writer.execute('CREATE TABLE t(x)');
      writer.execute('BEGIN IMMEDIATE');
      final originalFiles = failure.openFiles;
      failure.errorCode = SqlExtendedError.SQLITE_IOERR_SHMOPEN;
      failure.failMainOpenAt = failure.mainOpens + reopen;
      CommonDatabase? unexpected;
      addTearDown(() => unexpected?.close());

      expect(
        () => unexpected = openWritableDatabase(
          path,
          'reopened',
          busyTimeoutMs: 20,
        ),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.resultCode,
            'resultCode',
            SqlError.SQLITE_CANTOPEN,
          ),
        ),
      );
      expect(failure.openFiles, originalFiles);
      writer.execute('ROLLBACK');
    });
  }

  test('מסד מצב משתמש קיים ומוגן כתיבה עדיין נקרא', () async {
    final seed = UserStateDatabase.openAt(path);
    await seed.database;
    seed.close();
    final chmod = Process.runSync('chmod', ['444', path]);
    expect(chmod.exitCode, 0);
    addTearDown(() => Process.runSync('chmod', ['644', path]));
    final store = UserStateDatabase.openAt(path);
    addTearDown(store.close);
    final watch = Stopwatch()..start();

    final db = await store.database;
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(db.select('PRAGMA locking_mode').first.values.first, 'normal');
    expect(db.select('SELECT count(*) FROM lists').first.values.first, 0);
    expect(
      () => db.execute("INSERT INTO lists VALUES('x','y','{}',0)"),
      throwsA(
        isA<SqliteException>().having(
          (error) => error.resultCode,
          'resultCode',
          SqlError.SQLITE_READONLY,
        ),
      ),
    );
  }, skip: Platform.isWindows ? 'הרשאות POSIX' : false);

  for (final error in [
    SqlExtendedError.SQLITE_IOERR_SHMOPEN,
    SqlExtendedError.SQLITE_READONLY_CANTINIT,
  ]) {
    test('פתיחה מחדש עוזבת WAL בלי SHM ומשחררת את הנעילה ($error)', () {
      sqlite3.open(path)
        ..execute('PRAGMA journal_mode=WAL')
        ..execute('CREATE TABLE t(x)')
        ..execute('INSERT INTO t VALUES(1)')
        ..close();
      failure.errorCode = error;

      final db = openWritableDatabase(path, 'fallback');
      addTearDown(db.close);
      expect(db.select('PRAGMA journal_mode').first.values.first, 'delete');
      expect(db.select('PRAGMA locking_mode').first.values.first, 'normal');
      expect(db.select('PRAGMA synchronous').first.values.first, 2);
      db.execute('INSERT INTO t VALUES(2)');
      final reader = sqlite3.open(path)..execute('PRAGMA busy_timeout=20');
      addTearDown(reader.close);
      expect(reader.select('SELECT count(*) FROM t').first.values.first, 2);
    });
  }

  test('הפתיחה מחדש משמרת גם frames שטרם עברו checkpoint', () {
    final original = p.join(dir.path, 'original.db');
    final seed = sqlite3.open(original)
      ..execute('PRAGMA journal_mode=WAL')
      ..execute('PRAGMA wal_autocheckpoint=0')
      ..execute('CREATE TABLE t(x)');
    for (var i = 0; i < 100; i++) {
      seed.execute('INSERT INTO t VALUES(?)', [i]);
    }
    // עותק עקבי בזמן שאין כותב: ה-WAL מועתק בלי סגירה שמבצעת checkpoint.
    File(original).copySync(path);
    File('$original-wal').copySync('$path-wal');
    seed.close();
    expect(File('$path-wal').lengthSync(), greaterThan(0));
    failure.errorCode = SqlExtendedError.SQLITE_IOERR_SHMOPEN;

    final db = openWritableDatabase(path, 'pending-frames');
    addTearDown(db.close);
    expect(db.select('PRAGMA journal_mode').first.values.first, 'delete');
    expect(db.select('SELECT count(*) FROM t').first.values.first, 100);
    expect(db.select('SELECT sum(x) FROM t').first.values.first, 4950);
  });

  test('UserStateDatabase שומר timeout קצר גם אחרי fallback', () async {
    failure.errorCode = SqlExtendedError.SQLITE_IOERR_SHMOPEN;
    final store = UserStateDatabase.openAt(path);
    addTearDown(store.close);

    final db = await store.database;
    expect(db.select('PRAGMA journal_mode').first.values.first, 'delete');
    expect(db.select('PRAGMA busy_timeout').first.values.first, 1000);
    expect(db.select('SELECT count(*) FROM lists').first.values.first, 0);
  });
}
