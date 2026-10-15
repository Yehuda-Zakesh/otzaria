import 'package:flutter/foundation.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'database.dart';

/// גישה ל-`line_ref` — אינדקס ההפניות הקנוני `(bookId, refKeyHash) → lineIndex`.
///
/// הטבלה נבנית בבונה ה-DB, ולכן חסרה במסדים שנבנו לפניה; [isAvailable] מאפשר
/// לקורא ליפול חזרה למסלול ה-TOC במקום לסרוק.
/// שורה מועמדת מהאינדקס, עם ה-heRef שלה לאימות ההתאמה.
typedef LineRefCandidate = ({
  int bookId,
  int lineIndex,
  int lineId,
  String? heRef,
});

class LineRefDao {
  final MyDatabase _db;

  LineRefDao(this._db);

  Future<sqlite3.Database> get database => _db.database;

  /// ה-SQL האחרון של [candidatesForBooks] — לוודא בבדיקות איזה נוסח נשלח בפועל.
  @visibleForTesting
  String? lastCandidatesSql;

  /// האם המסד הנוכחי מכיל את טבלת האינדקס.
  Future<bool> isAvailable() async => (await _db.capabilities).hasLineRef;

  /// המועמדים למפתח [refKeyHash] בכל אחד מ-[bookIds] — שאילתה מאוגדת אחת,
  /// כדי שהקלדה מול כמה ספרים מועמדים לא תייצר רצף פניות. ה-heRef מוחזר כדי
  /// שהקורא יאמת את ההתאמה ולא יסתמך על ה-hash לבדו.
  Future<List<LineRefCandidate>> candidatesForBooks(
    List<int> bookIds,
    int refKeyHash,
  ) async {
    if (bookIds.isEmpty || !await isAvailable()) return const [];
    final db = await database;
    final sql = candidatesSql(bookIds, official: _db.isOfficial);
    lastCandidatesSql = sql;
    return db
        .select(sql, [refKeyHash])
        .map(
          (row) => (
            bookId: row['bookId'] as int,
            lineIndex: row['lineIndex'] as int,
            lineId: row['lineId'] as int,
            heRef: row['heRef'] as String?,
          ),
        )
        .toList();
  }

  /// בלי sqlite_stat1 המתכנן סורק את כל שורות הספר ב-line; ב-seforim.db
  /// CROSS JOIN מתחיל ממפתח line_ref. מסד אחר שומר על השאילתה המקורית.
  static String candidatesSql(
    Iterable<int> bookIds, {
    required bool official,
    String columns = 'lr.bookId, lr.lineIndex, l.id AS lineId, l.heRef',
  }) =>
      'SELECT $columns '
      'FROM line_ref lr '
      '${official ? 'CROSS JOIN' : 'JOIN'} line l '
      'ON l.bookId = lr.bookId AND l.lineIndex = lr.lineIndex '
      'WHERE lr.refKeyHash = ? AND lr.bookId IN (${bookIds.join(',')}) '
      'ORDER BY lr.bookId, lr.lineIndex';
}
