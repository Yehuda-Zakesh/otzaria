import 'dart:io' as io;

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/indexing/utils/book_source_hashes.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory tempDir;

  Future<void> openDatabase({required bool withContentHash}) async {
    final dbPath = p.join(tempDir.path, 'seforim.db');
    final database = MyDatabase.withPath(dbPath);
    await SeforimRepository(database).ensureInitialized();
    final db = await database.database;
    db.execute("INSERT INTO category (id, title, level) VALUES (1, 'א', 0)");
    db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
    if (withContentHash) {
      db.execute(
        'ALTER TABLE book ADD COLUMN contentHash INTEGER NOT NULL DEFAULT 0',
      );
    }
    for (final (id, hash) in [(5, 42), (6, -2), (7, 0)]) {
      db.execute(
        withContentHash
            ? "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines, contentHash) VALUES ($id, 1, 1, 'ספר $id', $id, 0, $hash)"
            : "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, totalLines) VALUES ($id, 1, 1, 'ספר $id', $id, 0)",
      );
    }
    database.close();
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  }

  setUp(() async {
    tempDir = await io.Directory.systemTemp.createTemp('otzaria_source_hash');
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    try {
      await tempDir.delete(recursive: true);
    } on io.FileSystemException {
      // Windows עלול להחזיק את קובץ המסד עוד רגע אחרי הסגירה.
    }
  });

  test('קורא את book.contentHash כ-u64; 0 = אין חותם', () async {
    await openDatabase(withContentHash: true);

    final hashes = await BookSourceHashes.load();

    expect(hashes.covers(BookSource.official), isTrue);
    expect(hashes.forSource(BookSource.official, 5), BigInt.from(42));
    expect(
      hashes.forSource(BookSource.official, 6),
      (BigInt.one << 64) - BigInt.two,
    );
    expect(hashes.forSource(BookSource.official, 7), isNull);
    expect(hashes.forSource(BookSource.user, 5), isNull);
  });

  test('מסד בלי העמודה — אין חותמים, והבדיקה נופלת לטביעת הטקסט', () async {
    await openDatabase(withContentHash: false);

    final hashes = await BookSourceHashes.load();

    expect(hashes.covers(BookSource.official), isFalse);
    expect(hashes.forSource(BookSource.official, 5), isNull);
  });
}
