import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingTocProvider provider;
  final bookA = TextBook(id: 1, title: 'ספר א', categoryId: 1, fileType: 'txt');
  final bookB = TextBook(id: 2, title: 'ספר ב', categoryId: 2, fileType: 'txt');
  final emptyBook = TextBook(
    id: 3,
    title: 'ספר ריק',
    categoryId: 3,
    fileType: 'txt',
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    provider = _CountingTocProvider();
    BooksCache.instance.setBooksForTesting([
      for (final book in [bookA, bookB, emptyBook])
        BookCacheEntry(
          id: book.id!,
          filePath: null,
          title: book.title,
          fileType: book.fileType!,
          categoryId: book.categoryId!,
          orderIndex: 0,
        ),
    ]);
    addTearDown(BooksCache.instance.clear);
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final book in [bookA, bookB, emptyBook])
          BookCompositeKey.fromBook(book)!: provider,
      },
      providers: [provider],
    );
    addTearDown(LibraryProviderManager.instance.resetForTesting);
  });

  TextBookRepository newRepository() =>
      TextBookRepository(fileSystem: FileSystemData.instance);

  test('טעינה חוזרת של אותו ספר אינה שולפת את תוכן העניינים שוב', () async {
    final repository = newRepository();

    final first = await repository.getTableOfContents(bookA);
    final second = await repository.getTableOfContents(bookA);

    expect(provider.calls, ['ספר א']);
    expect(identical(first, second), isTrue);
  });

  for (final source in [BookSource.user, BookSource.attached('custom')]) {
    test('אותו מופע ספר ממקור $source נטען מחדש אחרי עדכון', () async {
      final book = TextBook(
        id: bookA.id,
        title: bookA.title,
        categoryId: bookA.categoryId,
        source: source,
      );
      LibraryProviderManager.instance.seedMappingsForTesting(
        mapping: {BookCompositeKey.fromBook(book)!: provider},
        providers: [provider],
      );
      final repository = newRepository();
      await repository.getTableOfContents(book);

      provider.toc = [TocEntry(text: 'פרק חדש', index: 7, level: 1)];
      final updated = await repository.getTableOfContents(book);

      expect(updated.single.text, 'פרק חדש');
      expect(updated.single.index, 7);
      expect(provider.calls, [book.title, book.title]);
    });
  }

  test('מקור בפועל שהשתנה לאישי פוסל גם פגיעה קיימת במטמון', () async {
    final repository = newRepository();
    await repository.getTableOfContents(bookA);
    provider.resolvedSource = BookSource.user;
    provider.toc = [TocEntry(text: 'כותרת אישית', index: 3, level: 1)];
    final firstUser = await repository.getTableOfContents(bookA);
    provider.toc = [TocEntry(text: 'כותרת אישית מעודכנת', index: 6, level: 1)];
    final updatedUser = await repository.getTableOfContents(bookA);

    expect(firstUser.single.text, 'כותרת אישית');
    expect(updatedUser.single.text, 'כותרת אישית מעודכנת');
    expect(provider.calls, [bookA.title, bookA.title, bookA.title]);
  });

  test('ספר legacy מקובץ אינו נשמר גם כשהמקור רשמי', () async {
    BooksCache.instance.setBooksForTesting([
      BookCacheEntry(
        id: bookA.id!,
        filePath: '/personal/book.txt',
        title: bookA.title,
        fileType: 'txt',
        categoryId: bookA.categoryId!,
        orderIndex: 0,
      ),
    ]);
    final repository = newRepository();
    await repository.getTableOfContents(bookA);
    provider.toc = [TocEntry(text: 'כותרת מהקובץ המעודכן', index: 4, level: 1)];

    final updated = await repository.getTableOfContents(bookA);

    expect(updated.single.text, 'כותרת מהקובץ המעודכן');
    expect(provider.calls, [bookA.title, bookA.title]);
  });

  test('תוצאה לפני טעינת הקטלוג הרשמי אינה נשארת במטמון', () async {
    BooksCache.instance.clear();
    final repository = newRepository();
    await repository.getTableOfContents(bookA);
    provider.toc = [
      TocEntry(text: 'תוכן עניינים זמין כעת', index: 2, level: 1),
    ];

    final updated = await repository.getTableOfContents(bookA);

    expect(updated.single.text, 'תוכן עניינים זמין כעת');
    expect(provider.calls, [bookA.title, bookA.title]);
  });

  test('עדכון דור הספרייה פוסל TOC של אותו מופע ספר רשמי', () async {
    final repository = newRepository();
    await repository.getTableOfContents(bookA);
    BooksCache.instance.clear();
    BooksCache.instance.setBooksForTesting([
      BookCacheEntry(
        id: bookA.id!,
        filePath: null,
        title: bookA.title,
        fileType: 'txt',
        categoryId: bookA.categoryId!,
        orderIndex: 0,
      ),
    ]);
    provider.toc = [TocEntry(text: 'מהדורת ספרייה חדשה', index: 9, level: 1)];

    final updated = await repository.getTableOfContents(bookA);
    final repeated = await repository.getTableOfContents(bookA);

    expect(updated.single.text, 'מהדורת ספרייה חדשה');
    expect(updated.single.index, 9);
    expect(identical(updated, repeated), isTrue);
    expect(provider.calls, [bookA.title, bookA.title]);
  });

  test('תוצאת טעינה שחפפה לעדכון דור אינה נכנסת למטמון', () async {
    final repository = newRepository();
    final pending = Completer<List<TocEntry>>();
    provider.pending = pending;
    final loading = repository.getTableOfContents(bookA);
    expect(provider.calls, [bookA.title]);
    BooksCache.instance.clear();
    BooksCache.instance.setBooksForTesting([
      BookCacheEntry(
        id: bookA.id!,
        title: bookA.title,
        filePath: null,
        fileType: 'txt',
        categoryId: bookA.categoryId!,
        orderIndex: 0,
      ),
    ]);
    pending.complete([TocEntry(text: 'תוצאה מהדור הישן', index: 0, level: 1)]);
    await loading;
    provider.pending = null;
    provider.toc = [TocEntry(text: 'פרק מהדור החדש', index: 8, level: 1)];

    final updated = await repository.getTableOfContents(bookA);

    expect(updated.single.text, 'פרק מהדור החדש');
    expect(updated.single.index, 8);
    expect(provider.calls, [bookA.title, bookA.title]);
  });

  test('תוצאה שחפפה לשינוי מקור אינה נשמרת בשם המקור הרשמי', () async {
    final repository = newRepository();
    final pending = Completer<List<TocEntry>>();
    provider.pending = pending;
    final loading = repository.getTableOfContents(bookA);
    expect(provider.calls, [bookA.title]);
    provider.resolvedSource = BookSource.user;
    pending.complete([TocEntry(text: 'כותרת אישית', index: 3, level: 1)]);
    await loading;
    provider.pending = null;
    provider.resolvedSource = BookSource.official;
    provider.toc = [TocEntry(text: 'כותרת רשמית', index: 8, level: 1)];

    final official = await repository.getTableOfContents(bookA);

    expect(official.single.text, 'כותרת רשמית');
    expect(provider.calls, [bookA.title, bookA.title]);
  });

  test('ספר אחר, מופע ספר אחר ותוכן עניינים ריק נשלפים כמו קודם', () async {
    final repository = newRepository();

    final a = await repository.getTableOfContents(bookA);
    final b = await repository.getTableOfContents(bookB);
    expect(a.single.text, 'פרק של ספר א');
    expect(b.single.text, 'פרק של ספר ב');

    // מופע חדש של אותו ספר (מהדורה, פתיחה מחדש) אינו נחשב אותו ספר.
    final sameTitle = TextBook(
      id: 2,
      title: 'ספר ב',
      categoryId: 2,
      fileType: 'txt',
    );
    final b2 = await repository.getTableOfContents(sameTitle);
    expect(b2.single.text, 'פרק של ספר ב');

    // ריק עשוי להיות כשל זמני בעלייה, ולכן נשלף שוב בטעינה הבאה.
    expect(await repository.getTableOfContents(emptyBook), isEmpty);
    expect(await repository.getTableOfContents(emptyBook), isEmpty);

    // מאגר נפרד (טאב אחר) שולף בעצמו.
    final other = await newRepository().getTableOfContents(bookA);
    expect(other.single.text, 'פרק של ספר א');

    expect(provider.calls, [
      'ספר א',
      'ספר ב',
      'ספר ב',
      'ספר ריק',
      'ספר ריק',
      'ספר א',
    ]);
  });
}

class _CountingTocProvider implements DatabaseLibraryProvider {
  final calls = <String>[];
  List<TocEntry>? toc;
  Completer<List<TocEntry>>? pending;
  BookSource resolvedSource = BookSource.official;

  @override
  BookSource? resolvedSourceForBook(TextBook book) => resolvedSource;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    calls.add(title);
    if (title == 'ספר ריק') return const [];
    if (pending != null) return pending!.future;
    return toc ?? [TocEntry(text: 'פרק של $title', index: 0, level: 1)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
