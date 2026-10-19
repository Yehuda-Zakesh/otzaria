import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/toc_entry.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

class TocDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;
  Map<String, String>? _resolvedQueries;

  TocDao(this._db) {
    _queries = QueryLoader.loadQueries('TocQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  /// ל-seforim.db v3 אין עמודת tocEntry.lineIndex (רק lineId), ואזכור שלה
  /// היה מפיל את השאילתה ב-prepare. null — אין במסד טבלאות TOC.
  Future<Map<String, String>?> _resolved() async {
    if (_resolvedQueries != null) return _resolvedQueries!;
    final capabilities = await _db.capabilities;
    if (!capabilities.hasToc) return null;
    _resolvedQueries = capabilities.hasTocEntryLineIndex
        ? _queries
        : {
            for (final e in _queries.entries)
              e.key: e.value.replaceAll(
                'l.lineIndex, t.lineIndex, t.lineId',
                'l.lineIndex, t.lineId',
              ),
          };
    return _resolvedQueries!;
  }

  /// שורות ה-TOC הגולמיות של הספר. מוחזרות כמפות כדי שיוכלו לחצות גבול
  /// isolate; [selectByBookId] הוא העיטוף שממפה אותן ל-[TocEntry].
  Future<List<Map<String, dynamic>>> selectRowsByBookId(int bookId) async {
    final queries = await _resolved();
    if (queries == null) return const [];
    final db = await database;
    return db.select(queries['selectByBookId']!, [bookId]).toMapList();
  }

  Future<List<TocEntry>> selectByBookId(int bookId) async {
    final rows = await selectRowsByBookId(bookId);
    return rows.map((row) => TocEntry.fromMap(row)).toList();
  }

  Future<int> insertTocEntry(TocEntry entry) async {
    final db = await database;
    return insertTocEntrySync(db, entry);
  }

  /// גרעין סינכרוני של [insertTocEntry] — לשימוש בתוך `withTransaction`.
  int insertTocEntrySync(sqlite3.Database db, TocEntry entry) {
    db.execute(_queries['insert']!, [
      entry.bookId,
      entry.parentId,
      entry.textId,
      entry.level,
      entry.lineId,
      entry.lineIndex,
      entry.isLastChild ? 1 : 0,
      entry.hasChildren ? 1 : 0,
    ]);
    return db.lastInsertRowId;
  }
}
