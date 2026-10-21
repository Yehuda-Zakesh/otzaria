import 'package:otzaria/data/book_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';

class _FakeSearchResult {
  final String filePath;

  _FakeSearchResult(this.filePath);
}

void main() {
  group('FacetHelper.buildFacetCountsFromResults', () {
    test('מחשב ספירות עבור שורש, אבות וספרים', () {
      final genesis = TextBook(
        id: 101,
        title: 'בראשית',
        categoryPath: '/תנ"ך/תורה',
      );
      final berachot = TextBook(
        id: 202,
        title: 'ברכות',
        categoryPath: '/משנה/זרעים',
      );

      final bookByIndexedFilePath = <String, Book>{
        BookIdentity.indexedFilePath(genesis): genesis,
        BookIdentity.indexedFilePath(berachot): berachot,
      };

      final counts = FacetHelper.buildFacetCountsFromResults(
        [
          _FakeSearchResult(
            BookIdentity.indexedFilePath(genesis),
          ),
          _FakeSearchResult(
            BookIdentity.indexedFilePath(berachot),
          ),
        ],
        bookByIndexedFilePath,
      );

      expect(counts['/'], 2);
      expect(counts['/תנ"ך'], 1);
      expect(counts['/תנ"ך/תורה'], 1);
      expect(counts['/תנ"ך/תורה/id:101'], 1);
      expect(counts['/משנה'], 1);
      expect(counts['/משנה/זרעים'], 1);
      expect(counts['/משנה/זרעים/id:202'], 1);
    });

    test('מבדיל בין ספרים עם אותו שם לפי מפתח ה-filePath היציב', () {
      final firstBook = TextBook(
        id: 11,
        title: 'שבת',
        categoryPath: '/תלמוד בבלי/סדר מועד',
      );
      final secondBook = TextBook(
        id: 22,
        title: 'שבת',
        categoryPath: '/הלכה',
      );

      final counts = FacetHelper.buildFacetCountsFromResults(
        [
          _FakeSearchResult(
            BookIdentity.indexedFilePath(firstBook),
          ),
          _FakeSearchResult(
            BookIdentity.indexedFilePath(secondBook),
          ),
        ],
        {
          BookIdentity.indexedFilePath(firstBook): firstBook,
          BookIdentity.indexedFilePath(secondBook): secondBook,
        },
      );

      expect(counts['/תלמוד בבלי/סדר מועד/id:11'], 1);
      expect(counts['/הלכה/id:22'], 1);
    });

    test('תוצאה של ספר שכבר אינו בספרייה מדולגת בשקט', () {
      final counts = FacetHelper.buildFacetCountsFromResults(
        [_FakeSearchResult('uid:99')],
        const <String, Book>{},
      );

      expect(counts, isEmpty);
    });
  });

  group('FacetHelper.buildFacetCountsFromBookCounts', () {
    test('מחשב ספירות אגרגטיביות ממפת ספרים ייחודית', () {
      final genesis = TextBook(
        title: 'בראשית',
        id: 101,
        categoryPath: '/תנ"ך/תורה',
      );
      final berachot = TextBook(
        title: 'ברכות',
        id: 202,
        categoryPath: '/משנה/זרעים',
      );

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        {
          BookIdentity.indexedFilePath(genesis): 3,
          BookIdentity.indexedFilePath(berachot): 2,
        },
        {
          BookIdentity.indexedFilePath(genesis): genesis,
          BookIdentity.indexedFilePath(berachot): berachot,
        },
      );

      expect(counts['/'], 5);
      expect(counts['/תנ"ך'], 3);
      expect(counts['/תנ"ך/תורה'], 3);
      expect(counts['/תנ"ך/תורה/id:101'], 3);
      expect(counts['/משנה'], 2);
      expect(counts['/משנה/זרעים'], 2);
      expect(counts['/משנה/זרעים/id:202'], 2);
    });

    test('מנרמל categoryPath עם פסיקים לפני בניית facets', () {
      final genesis = TextBook(
        title: 'בראשית',
        id: 101,
        categoryPath: 'תנ"ך, תורה',
      );

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        {
          BookIdentity.indexedFilePath(genesis): 1,
        },
        {
          BookIdentity.indexedFilePath(genesis): genesis,
        },
      );

      expect(counts['/'], 1);
      expect(counts['/תנ"ך'], 1);
      expect(counts['/תנ"ך/תורה'], 1);
      expect(counts['/תנ"ך/תורה/id:101'], 1);
      expect(counts.containsKey('/תנ"ך, תורה'), isFalse);
    });
  });

  group('FacetHelper.buildFacetCountsFromBookCounts — ספרים רבים בקטגוריה', () {
    late _CountingCategory leaf;
    late Map<String, int> bookCounts;
    late Map<String, Book> booksByKey;

    setUp(() {
      Category category(String title, Category? parent) => Category(
        title: title,
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: parent,
      );
      final root = category('ספריית אוצריא', null);
      final talmud = category('תלמוד בבלי', root);
      leaf = _CountingCategory(category('סדר מועד', talmud));
      bookCounts = {};
      booksByKey = {};
      for (var i = 0; i < 40; i++) {
        final book = TextBook(title: 'מסכת $i', id: 300 + i, category: leaf);
        final key = BookIdentity.indexedFilePath(book);
        bookCounts[key] = i + 1;
        booksByKey[key] = book;
      }
      final loose = TextBook(title: 'ספר בלי קטגוריה', id: 900);
      final looseKey = BookIdentity.indexedFilePath(loose);
      bookCounts[looseKey] = 7;
      booksByKey[looseKey] = loose;
    });

    test('נתיב הקטגוריה מחושב פעם אחת לקטגוריה ולא לכל ספר', () {
      FacetHelper.buildFacetCountsFromBookCounts(bookCounts, booksByKey);
      expect(leaf.pathReads, lessThanOrEqualTo(3));
    });

    test('הספירות זהות לחישוב ספר-ספר', () {
      final expected = <String, int>{};
      for (final MapEntry(:key, :value) in bookCounts.entries) {
        final book = booksByKey[key]!;
        final categoryPath = FacetHelper.resolveCategoryPath(book);
        FacetHelper.incrementFacet(
          expected,
          FacetHelper.buildBookFacet(categoryPath, book),
          value,
        );
        if (categoryPath != null && categoryPath.isNotEmpty) {
          FacetHelper.incrementFacetWithAncestors(
            expected,
            categoryPath,
            value,
          );
        } else {
          FacetHelper.incrementFacet(expected, '/', value);
        }
      }

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        bookCounts,
        booksByKey,
      );

      expect(counts, expected);
      expect(counts['/'], 827);
      expect(counts['/תלמוד בבלי/סדר מועד'], 820);
    });
  });
}

class _CountingCategory extends Category {
  _CountingCategory(Category source)
    : super(
        title: source.title,
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: source.parent,
      );

  int pathReads = 0;

  @override
  String get path {
    pathReads++;
    return super.path;
  }
}
