import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as db;
import 'package:otzaria/migration/models/category.dart' as db;
import 'package:otzaria/migration/models/toc_entry.dart' as db;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'קטלוג וחימום אמיתיים מאפשרים מטמון; התנגשות עם אישי נשארת טרייה',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final temp = await Directory.systemTemp.createTemp('otzaria_toc_source_');
      final databasePath = path.join(temp.path, 'seforim.db');
      final previousRoot = AppPaths.cachedDataRootPath;
      final provider = DatabaseLibraryProvider.instance;
      final manager = LibraryProviderManager.instance;
      final writer = MyDatabase.withPath(databasePath);
      final officialRepo = SeforimRepository(writer);
      addTearDown(() => temp.delete(recursive: true));
      addTearDown(() => AppPaths.debugOverrideDataRootPath(previousRoot));
      addTearDown(() async {
        (await FindRefDbIsolate.instance()).disposeForTesting();
        await provider.sqliteProvider.dispose();
        await UserBooksDatabaseHolder.instance.close();
        provider.clearCache();
        manager.resetForTesting();
        BooksCache.instance.clear();
        writer.close();
      });
      AppPaths.debugOverrideDataRootPath(path.join(temp.path, 'data'));
      await Settings.setValue(
        SettingsRepository.keyDbEffectivePath,
        databasePath,
      );
      await officialRepo.ensureInitialized();
      final sourceId = await officialRepo.insertSource('official', 0);
      final categoryId = await officialRepo.insertCategory(
        const db.Category(title: 'קטגוריה רשמית', level: 0),
      );
      final bookId = await officialRepo.insertBook(
        db.Book(title: 'ספר משותף', categoryId: categoryId, sourceId: sourceId),
      );
      await officialRepo.insertTocEntry(
        db.TocEntry(bookId: bookId, text: 'פרק רשמי', level: 1, lineIndex: 0),
      );
      writer.close();
      FileSystemData.instance.libraryPath = temp.path;
      await manager.initialize();
      await provider.initialize();
      expect(provider.isInitialized, isTrue);
      final catalog = await provider.buildLibraryCatalog({}, temp.path);
      final book = catalog.getAllBooks().whereType<TextBook>().single;
      expect(book.id, bookId);
      BooksCache.instance.clear();
      await BooksCache.instance.warmUp();
      expect(BooksCache.instance.isLoaded, isTrue);
      expect(BooksCache.instance.getBookById(bookId)!.filePath, isNull);
      final generation = BooksCache.instance.generation;
      void mapProvider(DatabaseLibraryProvider value) {
        manager.seedMappingsForTesting(
          mapping: {BookCompositeKey.fromBook(book)!: value},
          providers: [value],
        );
      }

      mapProvider(provider);
      final repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      final official = await repository.getTableOfContents(book);
      expect(official.single.text, 'פרק רשמי');
      expect(
        identical(official, await repository.getTableOfContents(book)),
        isTrue,
      );

      final temporaryFailure = _EmptyOnceProvider();
      mapProvider(temporaryFailure);
      final fallbackRepository = TextBookRepository(
        fileSystem: FileSystemData.instance,
      );
      expect(
        (await fallbackRepository.getTableOfContents(book)).single.text,
        'פרק רשמי',
      );
      expect(
        (await fallbackRepository.getTableOfContents(book)).single.text,
        'הספק חזר',
      );
      expect(temporaryFailure.calls, 2);

      final personalRepo = await UserBooksDatabaseHolder.instance.repository;
      final personalSourceId = await personalRepo.insertSource('Personal', -1);
      final personalCategoryId = await personalRepo.insertCategory(
        const db.Category(title: 'ספרים אישיים', level: 0),
      );
      expect(personalCategoryId, categoryId);
      final personalBookId = await personalRepo.insertBook(
        db.Book(
          title: book.title,
          categoryId: personalCategoryId,
          sourceId: personalSourceId,
          fileType: 'txt',
        ),
      );
      await personalRepo.insertTocEntry(
        db.TocEntry(
          bookId: personalBookId,
          text: 'פרק אישי',
          level: 1,
          lineIndex: 3,
        ),
      );
      await provider.buildLibraryCatalog({}, temp.path);
      mapProvider(provider);
      expect(provider.resolvedSourceForBook(book), BookSource.user);
      expect(BooksCache.instance.generation, generation);
      expect(
        (await repository.getTableOfContents(book)).single.text,
        'פרק אישי',
      );

      await personalRepo.replaceExternalBookToc(personalBookId, [
        db.TocEntry(
          bookId: personalBookId,
          text: 'פרק אישי מעודכן',
          level: 1,
          lineIndex: 7,
        ),
      ]);
      final updated = await repository.getTableOfContents(book);
      expect(updated.single.text, 'פרק אישי מעודכן');
      expect(updated.single.index, 7);
    },
  );
}

class _EmptyOnceProvider implements DatabaseLibraryProvider {
  int calls = 0;

  @override
  BookSource? resolvedSourceForBook(TextBook book) => BookSource.official;

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    return ++calls == 1 ? [] : [TocEntry(text: 'הספק חזר', index: 1, level: 1)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
