import 'dart:async';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  FindRefDbIsolate? worker;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_acronym_worker');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AcronymsCache.instance.clear();
  });

  tearDown(() async {
    AcronymsCache.instance.clear();
    worker?.disposeForTesting();
    await SqliteDataProvider.instance.dispose();
    await tempDir.delete(recursive: true);
  });

  test(
    'חימום ראשון על DB גדול אינו חוסם את ה-event loop ושומר התאמות',
    () async {
      final dbPath = path.join(tempDir.path, 'seforim.db');
      final database = MyDatabase.withPath(dbPath);
      final db = await database.database;
      db.execute(
        "INSERT INTO category (id, title, level) VALUES (7, 'תנך', 0)",
      );
      db.execute("INSERT INTO source (id, name) VALUES (1, 'אוצריא')");
      db.execute(
        "INSERT INTO book (id, categoryId, sourceId, title, orderIndex, "
        "filePath, fileType) VALUES "
        "(1, 7, 1, 'ספר גדול', 1, '/b/large.txt', 'txt'), "
        "(2, 7, 1, 'משנה תורה', 2, '/b/rambam.txt', 'txt')",
      );
      db.execute('''
        WITH digits(d) AS (
          VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)
        ), numbers(n) AS (
          SELECT a.d + b.d * 10 + c.d * 100 + d.d * 1000 + e.d * 10000
          FROM digits a, digits b, digits c, digits d, digits e
        )
        INSERT INTO book_acronym (bookId, term)
        SELECT 1, 'כינוי ' || printf('%05d', n)
        FROM numbers
        WHERE n < 60000
      ''');
      db.execute(
        "INSERT INTO book_acronym (bookId, term) VALUES "
        "(2, 'רמב\"ם'), (2, 'משנה תורה')",
      );
      database.close();

      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await SqliteDataProvider.instance.initialize();
      worker = await FindRefDbIsolate.instance();

      var eventLoopTicks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => eventLoopTicks++,
      );
      try {
        await AcronymsCache.instance.warmUp().timeout(
          const Duration(seconds: 30),
        );
      } finally {
        timer.cancel();
      }

      expect(eventLoopTicks, greaterThan(5));
      expect(AcronymsCache.instance.isLoaded, isTrue);
      expect(
        AcronymsCache.instance.getAcronymsForBook(1),
        hasLength(60000),
      );
      expect(
        AcronymsCache.instance.getAcronymsForBook(2),
        unorderedEquals(['רמבם', 'משנה תורה']),
      );
      final candidates = AcronymsCache.instance.candidatesFor('רמבם')!;
      expect(candidates.length, 1);
      expect(candidates.contains(2), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
