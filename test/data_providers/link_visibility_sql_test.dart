import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/link_visibility_sql.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// נראות פר-צד (סכמה 3), נבדקת דרך **שאילתות הייצור עצמן** — הוקי
/// ה-`…ForTesting` של [DatabaseLibraryProvider] — ולא דרך SQL שהטסט מנסח
/// לעצמו. אחרת החלפת `displayedSide` באחד מאתרי ההזרקה הייתה עוברת בשקט.
void main() {
  late Directory tmp;

  /// מסד בצורת הסכמה האמיתית: A (בסיס) ↔ B (מצטט).
  /// link 1: A→B OTHER, צד 0 יידוכא — ציטוט "פרק שלם", כולל שורת coverage
  /// link 2: A→B OTHER, גלוי
  /// link 3: A→B COMMENTARY — תלוי-טקסט, עולה הפוך תמיד
  /// link 4: A→B OTHER, צד 1 מדוכא
  /// link 5: A→B OTHER, שני הצדדים מדוכאים
  String buildDb({required bool withTable, bool populate = true}) {
    final path = '${tmp.path}/links_${withTable}_$populate.db';
    final db = sqlite3.sqlite3.open(path);
    db.execute('''
      CREATE TABLE category (id INTEGER PRIMARY KEY, parentId INTEGER, title TEXT,
        level INTEGER, orderIndex INTEGER, heShortDesc TEXT, heDesc TEXT);
      CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE book (id INTEGER PRIMARY KEY, categoryId INTEGER, sourceId INTEGER,
        title TEXT, heRef TEXT, heShortDesc TEXT, notesContent TEXT, orderIndex INTEGER,
        isBaseBook INTEGER, totalLines INTEGER, hasAltStructures INTEGER,
        hasTeamim INTEGER, hasNekudot INTEGER, dependenceType TEXT, filePath TEXT,
        fileType TEXT);
      CREATE TABLE line (id INTEGER PRIMARY KEY, bookId INTEGER, lineIndex INTEGER,
        content TEXT, heRef TEXT, tocEntryId INTEGER, charCount INTEGER);
      CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER, targetBookId INTEGER,
        sourceLineId INTEGER, targetLineId INTEGER, targetLineIndex INTEGER,
        targetBookOrderIndex INTEGER, connectionTypeId INTEGER, baseProvenance INTEGER);
      CREATE TABLE link_anchor (linkId INTEGER, side INTEGER, charStart INTEGER,
        charEnd INTEGER, label TEXT, spans TEXT, PRIMARY KEY (linkId, side, charStart));
      CREATE TABLE link_range (linkId INTEGER, side INTEGER, endLineId INTEGER,
        endLineIndex INTEGER, PRIMARY KEY (linkId, side));
      CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER, side INTEGER,
        PRIMARY KEY (lineId, linkId, side));

      INSERT INTO category VALUES (1,NULL,'cat',0,1,NULL,NULL);
      INSERT INTO source VALUES (1,'Sefaria');
      INSERT INTO book VALUES (1,1,1,'A','A',NULL,NULL,1,1,3,0,0,0,NULL,NULL,NULL),
                             (2,1,1,'B','B',NULL,NULL,2,0,3,0,0,0,NULL,NULL,NULL);
      INSERT INTO line VALUES (1,1,0,'a1','A 1',NULL,2),(2,1,1,'a2','A 2',NULL,2),
                              (3,1,2,'a3','A 3',NULL,2),(4,2,0,'b1','B 1',NULL,2),
                              (5,2,1,'b2','B 2',NULL,2),(6,2,2,'b3','B 3',NULL,2);
      INSERT INTO connection_type VALUES (1,'OTHER'),(2,'COMMENTARY');
      INSERT INTO link VALUES (1,1,2,1,4,0,2,1,0),(2,1,2,1,5,1,2,1,0),
                              (3,1,2,1,4,0,2,2,0),(4,1,2,3,6,2,2,1,0),
                              (5,1,2,2,6,2,2,1,0);
      -- link 1 משתרע על שתי שורות של A: השורה השנייה מגיעה דרך coverage
      INSERT INTO link_range VALUES (1,0,2,1);
      INSERT INTO link_coverage VALUES (2,1,0);
    ''');
    if (withTable) {
      db.execute(
        'CREATE TABLE link_suppressed_side (linkId INTEGER NOT NULL, '
        'side INTEGER NOT NULL, reasonMask INTEGER NOT NULL, '
        'PRIMARY KEY (linkId, side))',
      );
      if (populate) {
        db.execute(
          'INSERT INTO link_suppressed_side VALUES '
          '(1,0,4),(4,1,1),(5,0,1),(5,1,2)',
        );
      }
    }
    db.close();
    return path;
  }

  String buildSameBookDb({required bool withTable}) {
    final path = buildDb(withTable: withTable, populate: false);
    final db = sqlite3.sqlite3.open(path);
    db.execute('''
      INSERT INTO link VALUES (6,1,1,1,3,2,1,1,0),
                              (7,1,1,1,2,1,1,1,0),
                              (8,1,1,2,3,2,1,1,0),
                              (9,1,1,2,3,2,1,2,0),
                              (10,1,1,1,2,1,1,1,1);
      INSERT INTO link_range VALUES (7,0,2,1), (10,0,2,1);
      INSERT INTO link_coverage VALUES (2,7,0), (2,10,0);
    ''');
    if (withTable) {
      db.execute(
        'INSERT INTO link_suppressed_side VALUES (6,0,4),(8,1,1),(10,0,4)',
      );
    }
    db.close();
    return path;
  }

  Set<String> forwardSignatures(String path) =>
      DatabaseLibraryProvider.loadBookLinksRowsForTesting(
            dbPath: path,
            title: 'A',
            categoryId: 1,
            fileType: 'text',
          )
          .where((r) => r['connectionTypeName'] != 'SOURCE')
          .map(
            (r) =>
                '${r['sourceLineIndex']}:${r['targetLineIndex']}:'
                '${r['connectionTypeName']}',
          )
          .toSet();

  /// שורות שהספר המצטג B מקבל — כלומר הזרוע ההפוכה.
  List<Map<String, dynamic>> inverseRows(String path) =>
      DatabaseLibraryProvider.loadBookLinksRowsForTesting(
        dbPath: path,
        title: 'B',
        categoryId: 1,
        fileType: 'text',
      ).toList();

  Set<String> rangeSignatures(String path, String title) =>
      DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
            dbPath: path,
            title: title,
            categoryId: 1,
            fileType: 'text',
            startLineIndex: 0,
            endLineIndex: 2,
          )
          .map(
            (r) =>
                '${r['sourceLineIndex']}:${r['targetLineIndex']}:'
                '${r['connectionTypeName']}',
          )
          .toSet();

  Map<String, int> summaryCounts(String path, String title) => {
    for (final row
        in DatabaseLibraryProvider.loadBookLinkTargetsSummaryRowsForTesting(
          dbPath: path,
          title: title,
          categoryId: 1,
        ).rows)
      '${row['targetBookTitle']}:${row['connectionTypeName']}':
          row['linkCount'] as int,
  };

  List<Map<String, dynamic>> sameBookRows(String path) =>
      DatabaseLibraryProvider.loadBookLinksRowsForTesting(
        dbPath: path,
        title: 'A',
        categoryId: 1,
        fileType: 'text',
      ).where((row) => row['targetBookTitle'] == 'A').toList();

  setUp(() => tmp = Directory.systemTemp.createTempSync('linkvis'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('מסד ישן (אין טבלה) — התנהגות קודמת', () {
    test('הזרוע ההפוכה מחזירה רק תלויי-טקסט, מתויגים SOURCE', () {
      final rows = inverseRows(buildDb(withTable: false));
      expect(rows.map((r) => r['connectionTypeName']).toSet(), {'SOURCE'});
    });

    test('הקדמית מחזירה את כל שלושת הקישורים, כולל שורת ה-coverage', () {
      expect(forwardSignatures(buildDb(withTable: false)), {
        '0:0:OTHER',
        '1:0:OTHER',
        '0:1:OTHER',
        '0:0:COMMENTARY',
        '2:2:OTHER',
        '1:2:OTHER',
      });
    });

    test('מסלולי range ו-summary שומרים את התנהגות סכמה 2', () {
      final path = buildDb(withTable: false);
      expect(rangeSignatures(path, 'B'), {'0:0:SOURCE'});
      expect(summaryCounts(path, 'A'), {
        'B:OTHER': 5,
        'B:COMMENTARY': 1,
      });
      expect(summaryCounts(path, 'B'), {'A:SOURCE': 1});
    });
  });

  group('טבלת סכמה 3 ריקה — כל הצדדים גלויים', () {
    test('עצם קיום הטבלה מפעיל דו-כיווניות מלאה', () {
      final rows = inverseRows(buildDb(withTable: true, populate: false));
      expect(
        rows.where((r) => r['connectionTypeName'] == 'OTHER').length,
        4,
      );
      expect(rows.where((r) => r['connectionTypeName'] == 'SOURCE').length, 1);
    });
  });

  group('סכמה 3 — הקישור עובר צד', () {
    test('נעלם מספר הבסיס, כולל שורת ה-coverage שלו', () {
      expect(forwardSignatures(buildDb(withTable: true)), {
        '0:1:OTHER',
        '0:0:COMMENTARY',
        '2:2:OTHER',
      });
    });

    test('מופיע בספר המצטג, ומתויג בסוגו האמיתי ולא כ-SOURCE', () {
      final rows = inverseRows(buildDb(withTable: true));
      final types = rows.map((r) => r['connectionTypeName']).toList();
      expect(
        types,
        containsAll(['OTHER', 'SOURCE']),
        reason: 'המועבר שומר OTHER; תלוי-הטקסט נשאר SOURCE',
      );
      // link 2 גלוי בשני הצדדים ולכן מופיע בשניהם; link 4/5 מדוכאים בצד 1.
      expect(types.where((t) => t == 'OTHER').length, 2);
    });

    test('טווח הפרק נשמר על הקישור המועבר', () {
      final moved = inverseRows(
        buildDb(withTable: true),
      ).firstWhere((r) => r['connectionTypeName'] == 'OTHER');
      expect(moved['targetRangeEndLineIndex'], 1);
    });

    test('מסלול range מסנן את שני הצדדים לפי ה-verdict שלהם', () {
      final path = buildDb(withTable: true);
      expect(rangeSignatures(path, 'A'), {
        '0:1:OTHER',
        '0:0:COMMENTARY',
        '2:2:OTHER',
      });
      expect(rangeSignatures(path, 'B'), {
        '0:0:OTHER',
        '1:0:OTHER',
        '0:0:SOURCE',
      });
    });

    test('מסלול summary מסנן side 0 ו-side 1 בנפרד', () {
      final path = buildDb(withTable: true);
      expect(summaryCounts(path, 'A'), {
        'B:OTHER': 2,
        'B:COMMENTARY': 1,
      });
      expect(summaryCounts(path, 'B'), {
        'A:OTHER': 2,
        'A:SOURCE': 1,
      });
    });
  });

  group('קישורי הפניה בתוך אותו ספר', () {
    test('בסכמה 2 נשמרת ההתנהגות הישנה ללא זרוע הפוכה', () {
      final signatures =
          sameBookRows(
            buildSameBookDb(withTable: false),
          ).map(
            (row) =>
                '${row['sourceLineIndex']}:${row['targetLineIndex']}:'
                '${row['connectionTypeName']}',
          );

      expect(signatures, isNot(contains('2:0:OTHER')));
      expect(signatures, isNot(contains('2:1:SOURCE')));
    });

    test('צד 0 מדוכא עובר לעוגן צד 1 שאינו חופף', () {
      final path = buildSameBookDb(withTable: true);
      final fullRows = sameBookRows(path);
      final rangedRows = rangeSignatures(path, 'A');

      expect(
        fullRows
            .where(
              (row) =>
                  row['sourceLineIndex'] == 2 &&
                  row['targetLineIndex'] == 0 &&
                  row['connectionTypeName'] == 'OTHER',
            )
            .length,
        1,
      );
      expect(rangedRows, contains('2:0:OTHER'));
    });

    test('עוגן חופף נשאר בצד 0 ואינו מוכפל מהצד ההפוך', () {
      final rows = sameBookRows(buildSameBookDb(withTable: true));

      expect(
        rows.where(
          (row) =>
              row['sourceLineIndex'] == 1 &&
              row['targetLineIndex'] == 0 &&
              row['connectionTypeName'] == 'OTHER' &&
              row['baseProvenance'] == 0,
        ),
        isEmpty,
      );
      expect(
        rows.where(
          (row) =>
              row['sourceLineIndex'] == 1 &&
              row['targetLineIndex'] == 1 &&
              row['connectionTypeName'] == 'OTHER',
        ),
        hasLength(1),
      );
    });

    test('עוגן חופף עובר לצד 1 כשצד 0 מדוכא', () {
      final path = buildSameBookDb(withTable: true);
      final fullRows = sameBookRows(path);
      final rangedRows = rangeSignatures(path, 'A');

      expect(
        fullRows.where(
          (row) =>
              row['sourceLineIndex'] == 1 &&
              row['targetLineIndex'] == 0 &&
              row['connectionTypeName'] == 'OTHER' &&
              row['baseProvenance'] == 1,
        ),
        hasLength(1),
      );
      expect(rangedRows, contains('1:0:OTHER'));
    });

    test('דיכוי צד 1 וקישור תלוי אינם פותחים זרוע הפוכה', () {
      final rows = sameBookRows(buildSameBookDb(withTable: true));

      expect(
        rows.where(
          (row) =>
              row['sourceLineIndex'] == 2 &&
              row['targetLineIndex'] == 1 &&
              row['connectionTypeName'] == 'OTHER',
        ),
        isEmpty,
      );
      expect(
        rows.where((row) => row['connectionTypeName'] == 'SOURCE'),
        isEmpty,
      );
    });

    test('summary מוסיף רק צד יעד שיש לו עוגן לא חופף', () {
      final rows =
          DatabaseLibraryProvider.loadBookLinkTargetsSummaryRowsForTesting(
            dbPath: buildSameBookDb(withTable: true),
            title: 'A',
            categoryId: 1,
          ).rows;
      final counts =
          rows
              .where(
                (row) =>
                    row['targetBookTitle'] == 'A' &&
                    row['connectionTypeName'] == 'OTHER',
              )
              .map((row) => row['linkCount'] as int)
              .toList()
            ..sort();

      expect(counts, [2, 3]);
    });
  });

  group('מזהה ספר היעד בזרוע ההפוכה', () {
    test('שתי הזרועות נושאות את מזהה ספר המקור כ-targetBookId', () {
      final path = buildDb(withTable: false);
      expect(inverseRows(path).map((r) => r['targetBookId']).toSet(), {1});
      final rangeRows =
          DatabaseLibraryProvider.loadBookLinksRowsInRangeForTesting(
            dbPath: path,
            title: 'B',
            categoryId: 1,
            fileType: 'text',
            startLineIndex: 0,
            endLineIndex: 2,
          );
      expect(rangeRows, isNotEmpty);
      expect(rangeRows.map((r) => r['targetBookId']).toSet(), {1});
    });
  });

  group('שברי ה-SQL', () {
    test('ריקים כשאין תמיכה — לא נפלט SQL', () {
      expect(suppressedSideFilter(false, displayedSide: 0), '');
    });
  });
}
