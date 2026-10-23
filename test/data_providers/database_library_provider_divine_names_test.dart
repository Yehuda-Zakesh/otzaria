import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// טעינת מופעי שמות הקודש (`line_divine_name`, סכמה 7): היכולת מזוהה לפי
/// קיום הטבלה. מסד בלי הטבלה — אין מופעים, בלי שגיאה.
void main() {
  late Directory tempDir;
  late String dbPath;
  late sqlite3.Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_db_divine');
    dbPath = path.join(tempDir.path, 'db.sqlite');
    db = sqlite3.sqlite3.open(dbPath);
    db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
    db.execute(
      'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
      'lineIndex INTEGER NOT NULL, content TEXT)',
    );
    db.execute(
      "INSERT INTO book (id, title) VALUES (1, 'בראשית'), (2, 'שמות')",
    );
    db.execute(
      "INSERT INTO line VALUES (10, 1, 0, 'בראשית ברא אלהים'), "
      "(11, 1, 1, 'ויאמר אלהים'), (12, 1, 2, 'אין כאן'), "
      "(20, 2, 0, 'ספר אחר אלהים')",
    );
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  void createTable() => db.execute(
    'CREATE TABLE line_divine_name (lineId INTEGER NOT NULL, '
    'charStart INTEGER NOT NULL, span INTEGER NOT NULL, '
    'PRIMARY KEY (lineId, charStart)) WITHOUT ROWID',
  );

  DivineNameSpans load([String title = 'בראשית']) =>
      DatabaseLibraryProvider.loadDivineNamesForTesting(
        dbPath: dbPath,
        bookTitle: title,
      );

  group('יכולת hasDivineNames', () {
    test('בלי הטבלה — כבויה', () {
      expect(DbCapabilities.probe(db).hasDivineNames, isFalse);
    });

    test('עם הטבלה — פעילה', () {
      createTable();
      expect(DbCapabilities.probe(db).hasDivineNames, isTrue);
    });

    test('טבלה חסרת עמודות — כבויה', () {
      db.execute('CREATE TABLE line_divine_name (lineId INTEGER)');
      expect(DbCapabilities.probe(db).hasDivineNames, isFalse);
    });

    test('טיוטה בלי span (charEnd/kind/source נפרדים) — כבויה', () {
      db.execute(
        'CREATE TABLE line_divine_name (lineId INTEGER, charStart INTEGER, '
        'charEnd INTEGER, kind INTEGER, source INTEGER)',
      );
      expect(DbCapabilities.probe(db).hasDivineNames, isFalse);
    });
  });

  test('מסד ישן בלי הטבלה — אין מופעים, בלי שגיאה', () {
    expect(load().isEmpty, isTrue);
  });

  test('המופעים לפי lineIndex, לספר המבוקש בלבד', () {
    createTable();
    db.execute(
      'INSERT INTO line_divine_name VALUES '
      '(11, 6, 677), (10, 11, 677), (20, 8, 677)', // אורך 5, מקור 2, סוג 5
    );

    final spans = load();
    expect(spans.length, 2);
    expect(spans.spansAt(0), [(start: 11, end: 16, kind: 5)]);
    expect(spans.spansAt(1), [(start: 6, end: 11, kind: 5)]);
    expect(spans.spansAt(2), isEmpty);
    expect(load('ספר שאינו קיים').isEmpty, isTrue);
  });

  test('span פגום — הטעינה נכשלת בקול (ונרשמת ביומן), בלי מופעים חלקיים', () {
    createTable();
    db.execute(
      'INSERT INTO line_divine_name VALUES (10, 11, 677), (11, 6, 5)', // אורך 0
    );
    expect(load, throwsFormatException);
  });

  test('תא שאינו מספר שלם — הטעינה נכשלת בקול, לא מדלגת על השורה', () {
    createTable();
    // טקסט לא מספרי: '677' היה מומר למספר בגלל זיקת INTEGER של העמודה.
    db.execute(
      "INSERT INTO line_divine_name VALUES (10, 11, 677), (11, 6, 'x677')",
    );
    expect(load, throwsFormatException);
  });

  test('דרך העטיפה האמיתית: span פגום — נרשם ביומן ומחזיר ריק', () async {
    createTable();
    db.execute(
      'INSERT INTO line_divine_name VALUES (10, 11, 677), (11, 6, 5)', // אורך 0
    );
    final previousRegistry = AttachedLibraryRegistry.instance;
    final registry = AttachedLibraryRegistry(idleTimeout: null)
      ..update([
        AttachedLibrary(
          slug: 'divine-bad',
          displayName: 'divine-bad',
          path: dbPath,
          addedAt: DateTime(2026),
        ),
      ]);
    AttachedLibraryRegistry.instance = registry;
    final logs = <String>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    try {
      final spans = await DatabaseLibraryProvider.instance.getDivineNameSpans(
        'בראשית',
        source: BookSource.attached('divine-bad'),
      );
      expect(spans.isEmpty, isTrue);
      expect(
        logs.where((l) => l.contains('getDivineNameSpans "בראשית"')),
        hasLength(1),
      );
    } finally {
      debugPrint = previousPrint;
      await registry.closeAll();
      AttachedLibraryRegistry.instance = previousRegistry;
    }
  });
}
