import 'dart:io' as io;

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/utils/book_facet_metadata_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('otzaria_facet_cache');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    dbPath = p.join(tempDir.path, 'seforim.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO author (id, name) VALUES (1, 'רש\"י')");
    db.execute('INSERT INTO book_author (bookId, authorId) VALUES (5, 1)');
    database.close();
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    BookFacetMetadataCache.instance.clear();
  });

  tearDown(() async {
    BookFacetMetadataCache.instance.clear();
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on io.FileSystemException {
      // Windows עלול להחזיק את קובץ המסד עוד רגע אחרי הסגירה.
    }
  });

  List<String> facetsOf(Book book) => BookFacetMetadataCache.instance
      .extraFacetsForBook(book, isFoundational: false)
      .where((facet) => facet.startsWith('/author/'))
      .toList();

  test('אחרי החלפת מסד, clear גורם לקריאת המחברים החדשים', () async {
    final book = TextBook(id: 5, title: 'ספר');
    await BookFacetMetadataCache.instance.warmUp();
    expect(facetsOf(book), ['/author/רש"י']);

    final writer = sqlite3.open(dbPath);
    writer.execute("UPDATE author SET name = 'רמב\"ן' WHERE id = 1");
    writer.close();

    await BookFacetMetadataCache.instance.warmUp();
    expect(
      facetsOf(book),
      ['/author/רש"י'],
      reason: 'בלי clear המטמון נשאר על המסד הקודם',
    );

    BookFacetMetadataCache.instance.clear();
    expect(facetsOf(book), isEmpty);
    await BookFacetMetadataCache.instance.warmUp();
    expect(facetsOf(book), ['/author/רמב"ן']);
  });
}
