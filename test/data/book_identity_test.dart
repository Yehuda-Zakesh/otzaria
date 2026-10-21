import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/search/book_facet.dart';

void main() {
  group('תאימות מפתחות שמורים בין הקטלוג, facets וה-SDK', () {
    final fixtures = <({Book book, String key})>[
      (book: TextBook(id: 5, title: 'שבת'), key: 'id:5'),
      (
        book: TextBook(id: 5, title: 'שבת', source: BookSource.user),
        key: 'uid:5',
      ),
      (
        book: TextBook(id: 5, title: 'שבת', source: BookSource.attached('lib')),
        key: 'db:lib:5',
      ),
      (
        book: TextBook(
          id: 5,
          title: 'שבת',
          source: BookSource.attached('lib-2'),
        ),
        key: 'db:lib-2:5',
      ),
      (
        book: TextBook(id: 5, title: 'שבת', externalLibraryId: 'oh:9'),
        key: 'ext:oh:9',
      ),
      (
        book: TextBook(
          id: 5,
          title: 'שבת',
          source: BookSource.user,
          externalLibraryId: 'oh:9',
        ),
        key: 'ext:oh:9',
      ),
      (
        book: TextBook(
          id: 5,
          title: 'שבת',
          source: BookSource.attached('lib'),
          externalLibraryId: 'oh:9',
        ),
        key: 'db:lib:5',
      ),
      (
        book: TextBook(title: 'שבת', externalLibraryId: ' OH:9 '),
        key: 'ext: OH:9 ',
      ),
      (book: TextBook(title: 'שבת', fileType: null), key: 'שבת||TextBook|'),
      (
        book: TextBook(
          title: 'שבת',
          externalLibraryId: '',
          categoryPath: '/תורה',
          filePath: r'C:\books\a.txt',
        ),
        key: r'שבת|/תורה|txt|C:\books\a.txt',
      ),
    ];

    for (final fixture in fixtures) {
      test(fixture.key, () {
        final book = fixture.book;
        expect(BookIdentity.keyOf(book), fixture.key);
        expect(BookIdentity.indexedFilePath(book), fixture.key);
        expect(PluginBookIdentity.uidOf(book), fixture.key);
        expect(
          BookFacet.buildFacetPath(
            title: book.title,
            topics: '',
            bookId: book.id,
            source: book.source,
            externalLibraryId: book.externalLibraryId,
            categoryPath: book.categoryPath,
            fileType: book.fileType ?? book.runtimeType.toString(),
            filePath: book.filePath,
          ),
          '${book.categoryPath ?? ''}/${fixture.key}',
        );
      });
    }
  });

  test('DOCX ועטיפתו שומרים את המפתח המילולי, עם id ובלעדיו', () {
    for (final fixture in [(5, 'uid:5'), (null, r'מסמך|אישי|docx|C:\a.docx')]) {
      final docx = DocxBook(
        id: fixture.$1,
        title: 'מסמך',
        path: r'C:\a.docx',
        categoryPath: 'אישי',
        source: BookSource.user,
      );
      for (final book in [docx, docx.toTextBook()]) {
        expect(BookIdentity.keyOf(book), fixture.$2);
        expect(BookIdentity.indexedFilePath(book), fixture.$2);
        expect(PluginBookIdentity.toJsonWithUid(book), {
          'id': fixture.$1,
          'type': 'docx',
          'bookId': 'מסמך',
          'source': 'user',
          'bookUid': fixture.$2,
        });
      }
    }
  });

  group('מפתח מסמך PDF נפרד מ-UID הקטלוג', () {
    final fixtures = <({PdfBook book, String uid, String indexed})>[
      (
        book: PdfBook(id: 5, title: 'שבת', path: r'C:\שבת.pdf'),
        uid: 'id:5',
        indexed: r'C:\שבת.pdf',
      ),
      (
        book: PdfBook(
          id: 5,
          title: 'שבת',
          path: r'C:\שבת.pdf',
          externalLibraryId: DatabaseConstants.talmudBavliPdfExternalLibraryId(
            'שבת',
          ),
        ),
        uid: 'ext:talmud-pdf:שבת',
        indexed: 'ext:talmud-pdf:שבת',
      ),
      (
        book: PdfBook(
          id: 5,
          title: 'שבת',
          path: r'Z:\שבת.pdf',
          source: BookSource.attached('lib'),
          externalLibraryId: 'oh:9',
        ),
        uid: 'db:lib:5',
        indexed: 'db:lib:5',
      ),
      (
        book: PdfBook(
          title: 'שבת',
          path: r'C:\שבת.pdf',
          externalLibraryId: 'hb:123',
        ),
        uid: 'ext:hb:123',
        indexed: 'ext:hb:123',
      ),
    ];

    for (final fixture in fixtures) {
      test(fixture.indexed, () {
        final book = fixture.book;
        expect(BookIdentity.keyOf(book), fixture.uid);
        expect(PluginBookIdentity.uidOf(book), fixture.uid);
        expect(BookIdentity.indexedFilePath(book), fixture.indexed);
        expect(
          BookIdentity.indexedPdfFilePath(
            bookId: book.id,
            source: book.source,
            externalLibraryId: book.externalLibraryId,
            filePath: book.path,
          ),
          fixture.indexed,
        );
      });
    }
  });

  test('חילוץ slug שומר תאימות למפתחות הקיימים ואינו מפענח מזהי ספקים', () {
    expect(BookIdentity.attachedSlugOfKey('db:ספרייה-1:42'), 'ספרייה-1');
    expect(BookIdentity.attachedSlugOfKey('id:42'), isNull);
    expect(BookIdentity.attachedSlugOfKey('uid:42'), isNull);
    expect(BookIdentity.attachedSlugOfKey('ext:hb:42'), isNull);
    expect(BookIdentity.attachedSlugOfKey('db::42'), isNull);
    expect(BookIdentity.attachedSlugOfKey('db:ספרייה-1'), isNull);
  });
}
