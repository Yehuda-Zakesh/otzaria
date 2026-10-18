import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/utils/pending_reindex_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory indexDir;

  setUp(() async {
    PendingReindexStore.resetMemoryForTesting();
    indexDir = await Directory.systemTemp.createTemp('otzaria_pending');
  });

  tearDown(() async {
    PendingReindexStore.resetMemoryForTesting();
    await indexDir.delete(recursive: true);
  });

  File fileOf(Directory dir) =>
      File(p.join(dir.path, PendingReindexStore.fileName));

  test('בלי אינדקס פתוח אין רשימה', () {
    expect(PendingReindexStore.forIndex(null), isNull);
  });

  test('נשמר לדיסק ושורד הפעלה מחדש', () async {
    final store = PendingReindexStore.forIndex(indexDir.path)!;

    expect(await store.save({'id:5', 'uid:9'}), isTrue);
    PendingReindexStore.resetMemoryForTesting();

    expect(await store.load(), {'id:5', 'uid:9'});
    expect(jsonDecode(fileOf(indexDir).readAsStringSync()), {
      'version': 1,
      'keys': ['id:5', 'uid:9'],
    });
    expect(File('${fileOf(indexDir).path}.tmp').existsSync(), isFalse);
  });

  test('רשימה ריקה מוחקת את הקובץ', () async {
    final store = PendingReindexStore.forIndex(indexDir.path)!;
    await store.save({'id:5'});

    expect(await store.save({}), isTrue);

    expect(fileOf(indexDir).existsSync(), isFalse);
    expect(await store.load(), isEmpty);
  });

  test('כשהכתיבה לדיסק נכשלת, הרשימה נשמרת בזיכרון לאותה הפעלה', () async {
    final missing = Directory(p.join(indexDir.path, 'missing'));
    final store = PendingReindexStore.forIndex(missing.path)!;

    expect(await store.save({'id:5'}), isFalse);

    expect(await store.load(), {'id:5'});
  });

  test('קובץ פגום או מגרסה אחרת אינו מפיל את הקריאה', () async {
    final store = PendingReindexStore.forIndex(indexDir.path)!;
    fileOf(indexDir).writeAsStringSync('{לא json');
    expect(await store.load(), isEmpty);

    fileOf(indexDir).writeAsStringSync(
      jsonEncode({
        'version': 99,
        'keys': ['id:5'],
      }),
    );
    expect(await store.load(), isEmpty);
  });

  test('בקשת בדיקה מלאה נשמרת גם בלי ספרים, ומתנקה במפורש', () async {
    final store = PendingReindexStore.forIndex(indexDir.path)!;

    await store.save({}, checkLibrary: true);
    PendingReindexStore.resetMemoryForTesting();
    expect(await store.checkLibraryPending(), isTrue);

    // שמירת רשימה בלי לציין את הבקשה אינה מוחקת אותה.
    await store.save({'id:5'});
    expect(await store.checkLibraryPending(), isTrue);

    await store.save({}, checkLibrary: false);
    expect(await store.checkLibraryPending(), isFalse);
    expect(fileOf(indexDir).existsSync(), isFalse);
  });

  test('מחיקת האינדקס או החלפתו מנקה את מה שנזכר בזיכרון', () async {
    final missing = Directory(p.join(indexDir.path, 'missing'));
    final store = PendingReindexStore.forIndex(missing.path)!;
    await store.save({'id:5'}, checkLibrary: true);

    PendingReindexStore.clearMemory();

    expect(await store.load(), isEmpty);
    expect(await store.checkLibraryPending(), isFalse);
  });
}
