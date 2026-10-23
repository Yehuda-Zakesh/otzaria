import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/zstd_test_lib.dart';

/// טעינת הערות השוליים (`line_note`, סכמה 7). מסד בסכמה 6 — בלי הטבלה —
/// ממשיך להיפתח, ואין הערות מהטבלה.
void main() {
  late Directory tempDir;
  late String dbPath;
  late sqlite3.Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_db_notes');
    dbPath = path.join(tempDir.path, 'db.sqlite');
    db = sqlite3.sqlite3.open(dbPath);
    db.execute('CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT)');
    // צורת סכמה 6: `line` צרה והתוכן ב-`line_content`.
    db.execute(
      'CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER NOT NULL, '
      'lineIndex INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE line_content (id INTEGER PRIMARY KEY, content TEXT)',
    );
    db.execute("INSERT INTO book (id, title) VALUES (1, 'ספר'), (2, 'אחר')");
    db.execute(
      'INSERT INTO line VALUES (10, 1, 0), (11, 1, 1), (12, 1, 2), (20, 2, 0)',
    );
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  void createTable() => db.execute(
    'CREATE TABLE line_note (lineId INTEGER NOT NULL, '
    'noteIndex INTEGER NOT NULL, charPos INTEGER NOT NULL, '
    'hasMarker INTEGER NOT NULL, body TEXT NOT NULL, '
    'PRIMARY KEY (lineId, noteIndex)) WITHOUT ROWID',
  );

  // השורות השמורות, עם סימן לכל הערה שיש לה hasMarker (המחולל אינו שומר את טקסטו).
  void lines(Map<int, Object> contents) {
    for (final MapEntry(:key, :value) in contents.entries) {
      db.execute('INSERT INTO line_content VALUES (?, ?)', [key, value]);
    }
  }

  String sup(String marker) => '<sup class="footnote-marker">$marker</sup>';

  void createNamesTable() => db.execute(
    'CREATE TABLE line_note_divine_name (lineId INTEGER NOT NULL, '
    'noteIndex INTEGER NOT NULL, charStart INTEGER NOT NULL, '
    'span INTEGER NOT NULL, '
    'PRIMARY KEY (lineId, noteIndex, charStart)) WITHOUT ROWID',
  );

  BookNotes load([String title = 'ספר']) =>
      DatabaseLibraryProvider.loadBookNotesForTesting(
        dbPath: dbPath,
        bookTitle: title,
      );

  group('יכולת hasBookNotes', () {
    test('מסד בסכמה 6, בלי הטבלה — כבויה, והמסד עדיין מפוצל', () {
      final caps = DbCapabilities.probe(db);
      expect(caps.hasBookNotes, isFalse);
      expect(caps.hasSplitLineContent, isTrue);
    });

    test('עם הטבלה — פעילה', () {
      createTable();
      expect(DbCapabilities.probe(db).hasBookNotes, isTrue);
    });

    test('בלי charPos (טיוטה ישנה) — כבויה', () {
      db.execute(
        'CREATE TABLE line_note (lineId INTEGER, noteIndex INTEGER, '
        'marker TEXT, body TEXT)',
      );
      expect(DbCapabilities.probe(db).hasBookNotes, isFalse);
    });

    test('טבלה עם marker TEXT (טיוטת סכמה 7) במקום hasMarker — כבויה', () {
      db.execute(
        'CREATE TABLE line_note (lineId INTEGER NOT NULL, '
        'noteIndex INTEGER NOT NULL, charPos INTEGER NOT NULL, marker TEXT, '
        'body TEXT NOT NULL, PRIMARY KEY (lineId, noteIndex)) WITHOUT ROWID',
      );
      expect(DbCapabilities.probe(db).hasBookNotes, isFalse);
    });

    test('שמות בגוף ההערות — רק עם שתי הטבלאות', () {
      createTable();
      expect(DbCapabilities.probe(db).hasBookNoteDivineNames, isFalse);
      createNamesTable();
      expect(DbCapabilities.probe(db).hasBookNoteDivineNames, isTrue);
    });

    test('שמות בגוף ההערות בצורה הישנה (charEnd/kind/source) — כבויה', () {
      createTable();
      db.execute(
        'CREATE TABLE line_note_divine_name (lineId INTEGER, '
        'noteIndex INTEGER, charStart INTEGER, charEnd INTEGER, '
        'kind INTEGER, source INTEGER)',
      );
      expect(DbCapabilities.probe(db).hasBookNoteDivineNames, isFalse);
    });

    test('טבלה חסרת עמודות — כבויה', () {
      db.execute('CREATE TABLE line_note (lineId INTEGER, body TEXT)');
      expect(DbCapabilities.probe(db).hasBookNotes, isFalse);
    });
  });

  test('מסד בלי הטבלה — אין הערות, בלי שגיאה', () {
    expect(load().isEmpty, isTrue);
  });

  test('ההערות לפי lineIndex ובסדר noteIndex, לספר המבוקש בלבד', () {
    createTable();
    lines({10: 'גוף${sup('*')}', 11: 'אב${sup('א')} ג', 20: sup('א')});
    db.execute(
      "INSERT INTO line_note VALUES (11, 1, 9, 0, 'נספחת'), "
      "(11, 0, 3, 1, 'ראשונה'), (10, 0, 4, 1, '<b>גוף</b>'), "
      "(20, 0, 2, 1, 'ספר אחר')",
    );

    final notes = load();
    expect(notes.lineCount, 2);
    expect(notes.notesAt(0), [
      (noteIndex: 0, charPos: 4, marker: '*', body: '<b>גוף</b>'),
    ]);
    expect(notes.notesAt(1), [
      (noteIndex: 0, charPos: 3, marker: 'א', body: 'ראשונה'),
      (noteIndex: 1, charPos: 9, marker: null, body: 'נספחת'),
    ]);
    expect(notes.bodyDivineNames(1, 0), isEmpty);
    expect(notes.notesAt(2), isEmpty);
    expect(load('ספר שאינו קיים').isEmpty, isTrue);
  });

  group('גוף דחוס (מסגרת zstd, כמו line_content)', () {
    final zstd = openZstdForTests();
    final skip = zstd == null ? 'libzstd אינו זמין' : null;
    final dictionary = File(
      'test/fixtures/line_content_codec/dict.zdict',
    ).readAsBytesSync();
    Uint8List frame(String text) => compressWithDictionary(
      zstd!,
      Uint8List.fromList(utf8.encode(text)),
      dictionary,
    );

    setUpAll(() {
      if (zstd != null) LineContentCodec.openLibrary = () => zstd;
    });

    test('מפוענח לטקסט המדויק, לצד גוף TEXT', () {
      createTable();
      db.execute('CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY, dict BLOB)');
      db.execute('INSERT INTO zstd_dict VALUES (1, ?)', [dictionary]);
      lines({10: frame('גוף${sup('*')}'), 11: 'אב ג${sup('א')}'});
      final insert = db.prepare('INSERT INTO line_note VALUES (?, ?, ?, ?, ?)');
      insert
        ..execute([10, 0, 4, 1, frame('<b>גוף</b> "דחוס"\nשורה')])
        ..execute([11, 0, 3, 0, frame('')])
        ..execute([11, 1, 9, 1, 'גוף רגיל']);
      insert.close();

      final notes = load();
      expect(notes.notesAt(0), [
        (
          noteIndex: 0,
          charPos: 4,
          marker: '*',
          body: '<b>גוף</b> "דחוס"\nשורה',
        ),
      ]);
      expect(notes.notesAt(1), [
        (noteIndex: 0, charPos: 3, marker: null, body: ''),
        (noteIndex: 1, charPos: 9, marker: 'א', body: 'גוף רגיל'),
      ]);
    }, skip: skip);

    test('הקורא זורק על גוף BLOB במסד בלי zstd_dict', () {
      createTable();
      db.execute('INSERT INTO line_note VALUES (10, 0, 4, 0, ?)', [
        frame('גוף'),
      ]);
      expect(load, throwsFormatException);
    }, skip: skip);
  });

  group('הסימן משוחזר מהשורה', () {
    test(
      'ה-inner HTML המדויק של ה-<sup> ה-k-י, להערה ה-k-ית שיש לה hasMarker',
      () {
        createTable();
        lines({
          10:
              '${sup('')}א<SUP CLASS="footnote-marker"> <b>2</b>&amp; </SUP>'
              ' ב<sup>3</sup>',
        });
        db.execute(
          "INSERT INTO line_note VALUES (10, 0, 0, 1, 'ראשונה'), "
          "(10, 1, 1, 0, 'בלי סימן'), (10, 2, 2, 1, 'שלישית')",
        );
        expect(load().notesAt(0).map((n) => n.marker), [
          '',
          null,
          ' <b>2</b>&amp; ',
        ]);
      },
    );

    for (final (name, content, flags) in [
      ('פחות סימנים מהערות', 'א${sup('1')}', [1, 1]),
      ('יותר סימנים מהערות', 'א${sup('1')}${sup('2')}', [1, 0]),
      ('שורה בלי תוכן', null, [1]),
      ('hasMarker שאינו 0 או 1', 'א${sup('1')}', [2]),
    ]) {
      test('$name — שגיאה, לא סימן מנוחש', () {
        createTable();
        if (content != null) lines({10: content});
        for (var i = 0; i < flags.length; i++) {
          db.execute('INSERT INTO line_note VALUES (10, ?, 0, ?, ?)', [
            i,
            flags[i],
            'גוף $i',
          ]);
        }
        expect(load, throwsFormatException);
      });
    }
  });

  test('מופעי השמות בגוף ההערה לפי (lineIndex, noteIndex)', () {
    createTable();
    createNamesTable();
    lines({11: 'אב${sup('א')}ג${sup('ב')}', 20: sup('א')});
    db.execute(
      "INSERT INTO line_note VALUES (11, 0, 3, 1, 'אמר אלהים'), "
      "(11, 1, 5, 1, 'שנייה'), (20, 0, 2, 1, 'אלהים')",
    );
    db.execute(
      'INSERT INTO line_note_divine_name VALUES '
      '(11, 0, 4, 677), (20, 0, 0, 677)', // אורך 5, מקור 2, סוג 5
    );

    final notes = load();
    expect(notes.bodyDivineNames(1, 0), [(start: 4, end: 9, kind: 5)]);
    expect(notes.bodyDivineNames(1, 1), isEmpty);
    expect(notes.bodyDivineNames(0, 0), isEmpty);
  });

  group('שורת שם פגומה בגוף הערה — רק שכבת השמות נופלת', () {
    late List<String> logs;
    late DebugPrintCallback previousPrint;
    setUp(() {
      logs = [];
      previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    });
    tearDown(() => debugPrint = previousPrint);

    for (final (label, badRow) in [
      ('span פגום', '(11, 1, 0, 5)'), // אורך 0
      ('תא שאינו מספר', "(11, 1, 0, 'x677')"),
    ]) {
      test(label, () {
        createTable();
        createNamesTable();
        lines({11: 'אב${sup('א')}ג${sup('ב')}'});
        db.execute(
          "INSERT INTO line_note VALUES (11, 0, 3, 1, 'אמר אלהים'), "
          "(11, 1, 5, 1, 'שנייה')",
        );
        db.execute(
          'INSERT INTO line_note_divine_name VALUES (11, 0, 4, 677), $badRow',
        );

        final notes = load();
        expect(notes.notesAt(1), hasLength(2));
        expect(notes.bodyDivineNames(1, 0), isEmpty);
        expect(notes.bodyDivineNames(1, 1), isEmpty);
        expect(
          logs.where((l) => l.contains('getBookNotes divine names')),
          hasLength(1),
        );
      });
    }
  });
}
