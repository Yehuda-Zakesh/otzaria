import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Benchmark ידני מול ספרייה אמיתית: מריצים עם
/// `OTZARIA_BENCH_DB=/path/to/seforim.db flutter test test/find_ref/reference_books_cache_real_db_benchmark_test.dart`.
/// אינו חלק מבדיקות ה-CI, משום שזמן ביצוע אינו תנאי נכונות יציב.
void main() {
  final dbPath = Platform.environment['OTZARIA_BENCH_DB'];

  test('זמני התאמת ספרים על קטלוג אמיתי', () {
    final db = sqlite3.sqlite3.open(dbPath!, mode: sqlite3.OpenMode.readOnly);
    try {
      final books = db.select('SELECT id, title, orderIndex FROM book');
      final acronyms = db.select('SELECT bookId, term FROM book_acronym');
      final bookEntries = <BookCacheEntry>[
        for (final row in books)
          BookCacheEntry(
            id: row['id'] as int,
            title: row['title'] as String,
            filePath: '',
            fileType: 'txt',
            categoryId: 0,
            orderIndex: (row['orderIndex'] as num).toDouble(),
          ),
      ];
      BooksCache.instance.setBooksForTesting(bookEntries);
      final acronymsByBook = <int, List<String>>{};
      for (final row in acronyms) {
        (acronymsByBook.putIfAbsent(
          row['bookId'] as int,
          () => [],
        )).add(row['term'] as String);
      }
      AcronymsCache.instance.setAcronymsForTesting(acronymsByBook);

      final stopwatch = Stopwatch()..start();
      ReferenceBooksCache.instance.seedForTesting(
        normalizedTitles: {
          for (final book in bookEntries)
            book.id: normalizeForFindRefMatch(book.title),
        },
        categoryPaths: const {},
      );
      final buildMs = stopwatch.elapsedMilliseconds;
      final queries = [
        'שולחן ערוך ג',
        'רמבם תפלה',
        'ברכות ב',
        'חדושי הלכות',
        'מאירי סנהדרין',
        'תפלה',
        'ראש בבא בתרא',
      ];
      debugPrint(
        'real-db books=${books.length} acronyms=${acronyms.length} '
        'buildMs=$buildMs',
      );
      for (final query in queries) {
        stopwatch
          ..reset()
          ..start();
        final cold = ReferenceBooksCache.instance.search(query, limit: 1000);
        final coldUs = stopwatch.elapsedMicroseconds;
        final warm = <int>[];
        for (var i = 0; i < 5; i++) {
          stopwatch
            ..reset()
            ..start();
          ReferenceBooksCache.instance.search(query, limit: 1000);
          warm.add(stopwatch.elapsedMicroseconds);
        }
        warm.sort();
        debugPrint(
          'real-db query="$query" hits=${cold.length} '
          'coldUs=$coldUs warmMedianUs=${warm[2]}',
        );
      }
    } finally {
      db.close();
      BooksCache.instance.clear();
      AcronymsCache.instance.clear();
      ReferenceBooksCache.instance.clear();
    }
  }, skip: dbPath == null || dbPath.isEmpty);
}
