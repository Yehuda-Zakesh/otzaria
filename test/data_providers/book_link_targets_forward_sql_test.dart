import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/link_visibility_sql.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late sqlite3.Database db;
  late int titleReads;

  setUp(() {
    titleReads = 0;
    db = sqlite3.sqlite3.openInMemory();
    // שם הספר נקרא דרך פונקציה סופרת, כדי למדוד כמה פעמים השאילתה ניגשת ל-book.
    db.createFunction(
      functionName: 'count_title',
      argumentCount: const sqlite3.AllowedArgumentCount(1),
      directOnly: false,
      function: (args) {
        titleReads++;
        return args.first;
      },
    );
    db.execute('''
      CREATE TABLE book_data (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
      CREATE VIEW book AS SELECT id, count_title(title) AS title FROM book_data;
      CREATE TABLE connection_type (id INTEGER PRIMARY KEY, name TEXT);
      CREATE TABLE link (id INTEGER PRIMARY KEY, sourceBookId INTEGER,
        targetBookId INTEGER, connectionTypeId INTEGER);
      CREATE TABLE link_coverage (lineId INTEGER, linkId INTEGER,
        side INTEGER, PRIMARY KEY (lineId, linkId, side));
      CREATE TABLE link_suppressed_side (linkId INTEGER, side INTEGER,
        PRIMARY KEY (linkId, side));
      INSERT INTO book_data VALUES (1, 'בראשית'), (2, 'רש"י'), (3, 'רמב"ן'),
        (4, 'רמב"ן');
      INSERT INTO connection_type VALUES (1, 'COMMENTARY'), (2, 'REFERENCE');
    ''');
  });

  tearDown(() => db.close());

  Map<String, int> summary() => {
    for (final row in db.select(
      bookLinkTargetsForwardSql(
        hasLinkRanges: true,
        suppressedFilter: suppressedSideFilter(true, displayedSide: 0),
      ),
      [1, 1],
    ))
      '${row['targetBookTitle']}:${row['connectionTypeName']}':
          row['linkCount'] as int,
  };

  test('שם ספר-היעד נשלף פעם לקבוצה ולא פעם לכל קישור', () {
    final insert = db.prepare('INSERT INTO link VALUES (?, 1, 2, 1)');
    for (var id = 1; id <= 500; id++) {
      insert.execute([id]);
    }
    insert.close();

    expect(summary(), {'רש"י:COMMENTARY': 500});
    expect(titleReads, lessThan(5));
  });

  test('ספירה זהה: טווחים, דיכוי, סוגים וכותרות כפולות', () {
    db.execute('''
      INSERT INTO link VALUES (1, 1, 2, 1), (2, 1, 2, 1), (3, 1, 2, 2),
        (4, 1, 3, 1), (5, 1, 4, 1), (6, 1, 4, 1), (7, 1, 2, 1),
        (8, 2, 3, 1);
      -- קישור 1 מכסה עוד שתי שורות, צד היעד אינו נספר.
      INSERT INTO link_coverage VALUES (10, 1, 0), (11, 1, 0), (12, 1, 1);
      INSERT INTO link_suppressed_side VALUES (7, 0), (6, 1);
    ''');

    expect(summary(), {
      'רש"י:COMMENTARY': 4,
      'רש"י:REFERENCE': 1,
      'רמב"ן:COMMENTARY': 3,
    });
  });
}
