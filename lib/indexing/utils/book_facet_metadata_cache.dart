import 'package:flutter/foundation.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/commentary_service.dart';

/// מטמון חד-פעמי לריצת אינדוקס: ממדי ה-facet הנוספים של כל ספר —
/// מחברים (`book_author`), תקופה (דרך [GenerationCache], בדליי
/// [CommentaryEra]) ודגל ספר-יסוד (`isBaseBook` ב-DB).
///
/// הממדים מוטבעים בזמן אינדוקס כערכי facet נוספים על שדה `topics` של
/// המנוע, תחת שורשים שמורים באנגלית (ראו FACET_DIMENSION_ROOTS במנוע):
/// `/author/<שם>`, `/era/<תקופה>`, `/base`. בסינון: OR בתוך ממד, AND בין
/// ממדים. ספר שאין לו נתון (מחבר/תקופה לא ידועים) פשוט לא ישא את ה-facet
/// ולא ייכלל בסינון לפי אותו ממד.
class BookFacetMetadataCache {
  BookFacetMetadataCache._();

  static final BookFacetMetadataCache instance = BookFacetMetadataCache._();

  bool _isLoaded = false;
  Future<void>? _loadingFuture;
  int _generation = 0;

  final Map<int, List<String>> _authorsByBookId = <int, List<String>>{};
  final Map<int, List<String>> _authorsByUserBookId = <int, List<String>>{};
  final Set<int> _baseBookIds = <int>{};
  final Set<int> _baseUserBookIds = <int>{};

  static const String _authorsSql = '''
        SELECT ba.bookId AS bookId, a.name AS name
        FROM book_author ba
        JOIN author a ON a.id = ba.authorId
      ''';

  static const String _baseBooksSql =
      'SELECT id FROM book WHERE isBaseBook = 1';

  Future<void> warmUp() async {
    if (_isLoaded) return;
    if (_loadingFuture != null) return _loadingFuture;
    final loading = _loadingFuture = _loadInternal(_generation);
    try {
      await loading;
    } finally {
      if (identical(_loadingFuture, loading)) _loadingFuture = null;
    }
  }

  /// מפנה את הנתונים אחרי החלפת מסד; הטעינה הבאה קוראת את המסד החדש.
  void clear() {
    _generation++;
    _isLoaded = false;
    _loadingFuture = null;
    _authorsByBookId.clear();
    _authorsByUserBookId.clear();
    _baseBookIds.clear();
    _baseUserBookIds.clear();
  }

  Future<void> _loadInternal(int generation) async {
    // התקופה מגיעה מ-GenerationCache — מחומם יחד כדי שהאינדוקס לא ירוץ
    // לפני שהדורות נטענו (ואז כל הספרים היו נטבעים בלי /era).
    await GenerationCache.instance.warmUp();

    final repository = SqliteDataProvider.instance.repository;
    if (repository == null) {
      debugPrint('[BookFacetMetadataCache] DB not initialized; skipping');
      return;
    }
    final authors = <int, List<String>>{};
    final userAuthors = <int, List<String>>{};
    final baseIds = <int>{};
    final userBaseIds = <int>{};
    try {
      final db = await repository.database.database;
      final capabilities = await repository.database.capabilities;
      if (capabilities.hasAuthors) {
        _accumulateAuthors(db.select(_authorsSql), authors);
      }
      if (capabilities.hasColumn('book', 'isBaseBook')) {
        for (final row in db.select(_baseBooksSql)) {
          final id = row['id'] as int?;
          if (id != null) baseIds.add(id);
        }
      }

      // ספרים אישיים — רק אם ה-DB שלהם כבר פתוח, בלי לכפות יצירה.
      final userRepo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
      if (userRepo != null) {
        try {
          final userDb = await userRepo.database.database;
          _accumulateAuthors(userDb.select(_authorsSql), userAuthors);
          for (final row in userDb.select(_baseBooksSql)) {
            final id = row['id'] as int?;
            if (id != null) userBaseIds.add(id);
          }
        } catch (e) {
          debugPrint('[BookFacetMetadataCache] user_books skipped: $e');
        }
      }
    } catch (e) {
      debugPrint('[BookFacetMetadataCache] warmup failed: $e');
      return;
    }
    // מסד שהוחלף באמצע הטעינה ([clear]) — הנתונים שנקראו כבר אינם שלו.
    if (generation != _generation) return;
    _authorsByBookId.addAll(authors);
    _authorsByUserBookId.addAll(userAuthors);
    _baseBookIds.addAll(baseIds);
    _baseUserBookIds.addAll(userBaseIds);
    _isLoaded = true;
    debugPrint(
      '[BookFacetMetadataCache] Loaded authors for '
      '${_authorsByBookId.length} books, ${_baseBookIds.length} base books',
    );
  }

  static void _accumulateAuthors(Iterable rows, Map<int, List<String>> into) {
    for (final row in rows) {
      final bookId = row['bookId'] as int?;
      final name = row['name'] as String?;
      if (bookId == null || name == null || name.trim().isEmpty) continue;
      into.putIfAbsent(bookId, () => <String>[]).add(name.trim());
    }
  }

  /// נתיבי ה-facet הממדיים של הספר, לפרמטר `extraFacets` של המנוע.
  /// [isFoundational] — סיווג ספרי-היסוד לפי נתיב הקטגוריה
  /// (FoundationalBookClassifier), שמשלים את דגל ה-DB.
  List<String> extraFacetsForBook(Book book, {required bool isFoundational}) {
    final facets = <String>[];
    final id = book.id;
    final authors = id == null ? null : _authorsFor(id, source: book.source);
    if (authors != null) {
      for (final author in authors) {
        facets.add('/author/${_sanitizeSegment(author)}');
      }
    }
    final eraName = _eraNameFor(book);
    if (eraName != null) {
      facets.add('/era/${_sanitizeSegment(eraName)}');
    }
    final isBase =
        isFoundational ||
        (id != null &&
            switch (book.source) {
              OfficialBookSource() => _baseBookIds.contains(id),
              UserBookSource() => _baseUserBookIds.contains(id),
              AttachedBookSource() => false,
            });
    if (isBase) {
      facets.add('/base');
    }
    return facets;
  }

  List<String>? _authorsFor(int bookId, {required BookSource source}) =>
      switch (source) {
        OfficialBookSource() => _authorsByBookId[bookId],
        UserBookSource() => _authorsByUserBookId[bookId],
        AttachedBookSource() => null,
      };

  /// שם התקופה לפי דלי [CommentaryEra] של הספר; null לדלי "שאר מפרשים"
  /// (ספר בלי דור ידוע) — עדיף שלא ישא facet מאשר שישא תקופה שגויה.
  static String? _eraNameFor(Book book) {
    final order = GenerationCache.instance.getOrderForBook(
      book.id,
      book.source,
    );
    if (order == CommentaryEra.other.order) return null;
    for (final era in CommentaryEra.values) {
      if (era.order == order) return era.hebrewName;
    }
    return null;
  }

  /// '/' הוא מפריד הרמות של facet — שם שמכיל אותו היה נקרא כהיררכיה.
  static String _sanitizeSegment(String value) =>
      value.replaceAll('/', '־').trim();
}
