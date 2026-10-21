import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

import '../../test_helpers/memory_cache_provider.dart';
import '../../utils/file/docx_golden_fixtures.dart';

typedef _ImportResult = ({
  int added,
  int updated,
  int errors,
  List<int> updatedIds,
});
typedef _ImportPath = ({
  String name,
  SeforimRepository repository,
  Future<_ImportResult> Function() run,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Directory folder;
  late MyDatabase syncDatabase;
  late List<_ImportPath> imports;
  String? previousDataRoot;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temp = await Directory.systemTemp.createTemp('external-import-paths-');
    folder = Directory(path.join(temp.path, 'ספרים'))..createSync();
    previousDataRoot = AppPaths.cachedDataRootPath;
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(path.join(temp.path, 'data'));
    final addedRepository = await UserBooksDatabaseHolder.instance.repository;
    syncDatabase = MyDatabase.withPath(path.join(temp.path, 'synced.db'));
    final syncedRepository = SeforimRepository(syncDatabase);
    await syncedRepository.ensureInitialized();
    final service = FileSyncService.createForWorker(
      syncedRepository,
      userBooksRepository: syncedRepository,
    );
    imports = [
      (
        name: 'הוספת תיקייה',
        repository: addedRepository,
        run: () async {
          final result = await DatabaseLibraryProvider.instance
              .scanAndAddExternalBooksFromFolder(
                folder.path,
                'ספרים',
                addedRepository,
              );
          expect(result.fatalError, isNull);
          return (
            added: result.addedBooks,
            updated: result.updatedBooks,
            errors: result.failedBooks,
            updatedIds: result.updatedBookIds,
          );
        },
      ),
      (
        name: 'סנכרון תיקייה',
        repository: syncedRepository,
        run: () async {
          final result = await service.syncCustomFoldersWithInputs(
            libraryPath: temp.path,
            customFolders: [
              CustomFolder(
                path: folder.path,
                addToDatabase: false,
                addedAt: DateTime(2026),
              ),
            ],
          );
          return (
            added: result.addedBooks,
            updated: result.updatedBooks,
            errors: result.errors.length,
            updatedIds: result.updatedBookIds,
          );
        },
      ),
    ];
  });

  tearDown(() async {
    DatabaseLibraryProvider.instance.clearCache();
    await UserBooksDatabaseHolder.instance.close();
    syncDatabase.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await temp.delete(recursive: true);
  });

  File textFile(String content) =>
      File(path.join(folder.path, 'ספר אישי.txt'))..writeAsStringSync(content);

  void change(File file, String content) {
    file.writeAsStringSync(content);
    file.setLastModifiedSync(DateTime(2030));
  }

  Future<List<Map<String, Object?>>> snapshot(
    SeforimRepository repository,
  ) async {
    final categories = {
      for (final category in await repository.getAllCategories())
        category.id: category,
    };
    List<String> categoryPath(int id) {
      final category = categories[id]!;
      return [
        if (category.parentId != null) ...categoryPath(category.parentId!),
        category.title,
      ];
    }

    final books = await repository.getAllBooksLean();
    books.sort((a, b) => a.title.compareTo(b.title));
    return [
      for (final book in books)
        {
          'title': book.title,
          'fileType': book.fileType,
          'filePath': book.filePath,
          'fileSize': book.fileSize,
          'lastModified': book.lastModified,
          'totalLines': book.totalLines,
          'category': categoryPath(book.categoryId),
          'source': (await repository.getSourceById(book.sourceId))?.name,
          'toc': await tocSnapshot(repository, book.id),
        },
    ];
  }

  Future<void> expectSameContent() async {
    expect(
      await snapshot(imports.first.repository),
      await snapshot(imports.last.repository),
    );
  }

  test(
    'שני המסלולים מייצרים אותם ספרים, קטגוריות וכותרות במגוון פורמטים',
    () async {
      final nested = Directory(path.join(folder.path, 'שיעורים'))..createSync();
      textFile('<h1>ספר אישי</h1>\n  <h2>פרק א</h2>\n### סעיף\nתוכן');
      File(path.join(nested.path, 'דף.html')).writeAsStringSync(
        '<html><body><h1>כותרת</h1><p>טקסט</p></body></html>',
      );
      File(path.join(nested.path, 'מסמך.docx')).writeAsBytesSync(
        buildDocx(document: documentXml(para('תוכן מסמך'))),
      );
      for (final importer in imports) {
        final result = await importer.run();
        expect(result.added, 3, reason: importer.name);
        expect(result.errors, 0, reason: importer.name);
        final repeated = await importer.run();
        expect(repeated.added, 0);
        expect(repeated.updated, 0);
        expect(repeated.errors, 0);
        for (final book in await importer.repository.getAllBooksLean()) {
          expect(await importer.repository.getLineContents(book.id), isEmpty);
        }
        expect(await importer.repository.getAllCategories(), hasLength(3));
      }
      await expectSameContent();
      // סימון המקור של כל מתאם נשמר; אינו חלק מתוכן הספר המשותף.
      expect(
        (await imports.first.repository.getAllBooksLean()).every(
          (b) => b.isPersonal,
        ),
        isTrue,
      );
      expect(
        (await imports.last.repository.getAllBooksLean()).every(
          (b) => !b.isPersonal,
        ),
        isTrue,
      );
      final synced = await imports.last.repository.database.database;
      expect(synced.select('SELECT * FROM book_topic'), isNotEmpty);
    },
  );

  test(
    'עדכון שומר זהות ומחליף כותרות; טקסט ללא כותרות מנקה TOC בשני המסלולים',
    () async {
      final file = textFile('<h1>ספר אישי</h1>\n<h2>פרק א</h2>');
      for (final importer in imports) {
        expect((await importer.run()).added, 1);
      }
      final ids = [
        for (final importer in imports)
          (await importer.repository.getAllBooksLean()).single.id,
      ];
      for (final content in [
        '<h1>ספר אישי</h1>\n## פרק ב\n### סעיף חדש',
        'תוכן ללא כותרות',
      ]) {
        change(file, content);
        for (var i = 0; i < imports.length; i++) {
          final importer = imports[i];
          final result = await importer.run();
          expect(result.updatedIds, [ids[i]], reason: importer.name);
          expect(result.errors, 0, reason: importer.name);
          final book = (await importer.repository.getAllBooksLean()).single;
          expect(book.id, ids[i]);
          expect(
            book.lastModified,
            file.statSync().modified.millisecondsSinceEpoch,
          );
        }
        await expectSameContent();
      }
      for (final importer in imports) {
        final book = (await importer.repository.getAllBooksLean()).single;
        expect(await importer.repository.getBookToc(book.id), isEmpty);
      }
    },
  );

  test('כשל TOC בשני המסלולים משמר ספר וחותמת, והניסיון הבא מצליח', () async {
    final file = textFile('<h1>ספר אישי</h1>\n<h2>פרק א</h2>');
    for (final importer in imports) {
      expect((await importer.run()).added, 1);
    }
    final before = [
      for (final importer in imports) await snapshot(importer.repository),
    ];
    change(file, '<h1>ספר אישי</h1>\n<h2>פרק ב</h2>');
    for (var i = 0; i < imports.length; i++) {
      final importer = imports[i];
      final db = await importer.repository.database.database;
      db.execute('''
        CREATE TRIGGER fail_toc BEFORE INSERT ON tocEntry
        BEGIN SELECT RAISE(FAIL, 'injected TOC failure'); END
      ''');
      expect((await importer.run()).errors, 1, reason: importer.name);
      expect(
        await snapshot(importer.repository),
        before[i],
        reason: importer.name,
      );
      db.execute('DROP TRIGGER fail_toc');
      expect((await importer.run()).updated, 1, reason: importer.name);
      final book = (await importer.repository.getAllBooksLean()).single;
      expect(
        (await importer.repository.getBookToc(book.id)).last.text,
        'פרק ב',
      );
    }
    await expectSameContent();
  });

  test(
    'מסמך פגום אינו מוכנס, ועדכון פגום משמר את הספר הישן בשני המסלולים',
    () async {
      final file = File(path.join(folder.path, 'מסמך.docx'))
        ..writeAsBytesSync(
          buildDocx(document: documentXml(para('תוכן תקין'))),
        );
      for (final importer in imports) {
        expect((await importer.run()).added, 1);
      }
      final before = [
        for (final importer in imports) await snapshot(importer.repository),
      ];
      change(file, 'not a DOCX');
      File(path.join(folder.path, 'פגום.docx')).writeAsStringSync('not a DOCX');
      for (var i = 0; i < imports.length; i++) {
        final importer = imports[i];
        expect((await importer.run()).errors, 2, reason: importer.name);
        expect(
          await snapshot(importer.repository),
          before[i],
          reason: importer.name,
        );
      }
      await expectSameContent();
    },
  );

  test('עדכון PDF משמר outline קיים ואינו פותח PDFium בשני המסלולים', () async {
    final file = File(path.join(folder.path, 'ספר.pdf'))
      ..writeAsStringSync('not a PDF');
    for (final importer in imports) {
      final repository = importer.repository;
      final root = await repository.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final category = await repository.insertCategory(
        Category(title: 'ספרים', parentId: root, level: 1),
      );
      final source = await repository.insertSource(
        CustomFolderSource.nameForFolder(folder.path),
        -1,
      );
      final id = await repository.insertExternalContentBook(
        categoryId: category,
        sourceId: source,
        title: 'ספר',
        filePath: file.path,
        fileType: 'pdf',
        fileSize: 0,
        lastModified: 0,
        tocEntries: [
          const TocEntry(bookId: 0, level: 1, text: 'פרק PDF', lineIndex: 2),
        ],
      );
      final before = await repository.getBookToc(id);
      expect((await importer.run()).updatedIds, [id]);
      expect(await repository.getBookToc(id), before);
      expect(
        (await repository.getAllBooksLean()).single.fileSize,
        file.statSync().size,
      );
    }
    await expectSameContent();
  });
}

Future<List<Object>> tocSnapshot(
  SeforimRepository repository,
  int bookId,
) async {
  final toc = await repository.getBookToc(bookId);
  final positions = {for (var i = 0; i < toc.length; i++) toc[i].id: i};
  return [
    for (final entry in toc)
      (
        entry.text,
        entry.level,
        entry.lineIndex,
        positions[entry.parentId],
        entry.hasChildren,
        entry.isLastChild,
      ),
  ];
}
