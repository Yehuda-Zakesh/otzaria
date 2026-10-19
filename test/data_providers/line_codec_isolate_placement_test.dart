import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/line.dart' as migration_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/tools/dictionary/repository/db_dictionary_book_source.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/zstd_test_lib.dart';
import '../test_helpers/memory_cache_provider.dart';

const _title = 'ספר דחוס';
final _lines = [for (var i = 0; i < 30; i++) 'שורה $i של הספר'];

/// כותרת נושא גלויה בשורה 5 וכותרת שאינה בטקסט בשורה 10: רק פענוח נכון
/// של השורות מסנן את הראשונה.
const _topics = {5: 'שורה 5 של', 10: 'הלכות עירובין'};

void _loadTestZstd() =>
    LineContentCodec.openLibrary = () => openZstdForTests()!;

/// קריאות טקסט שורה ממסד דחוס לא מפענחות על ה-UI isolate: ה-codec המזויף
/// כאן נטען רק ב-isolate הראשי, ורושם כל טעינה שלו.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final zstd = openZstdForTests();
  final skip = zstd == null ? 'libzstd אינו זמין' : null;
  final dictionary = File(
    'test/fixtures/line_content_codec/dict.zdict',
  ).readAsBytesSync();

  late Directory tempDir;
  late int categoryId;
  final mainIsolateOpens = <String>[];

  setUpAll(() {
    LineContentCodec.openLibrary = () {
      mainIsolateOpens.add(Isolate.current.debugName ?? '?');
      return zstd!;
    };
  });

  setUp(() async {
    mainIsolateOpens.clear();
    tempDir = await Directory.systemTemp.createTemp('otzaria-codec-placement');
    final libraryPath = path.join(tempDir.path, 'library');
    await Directory(libraryPath).create(recursive: true);
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');

    final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
    categoryId = await _seedDb(dbPath);
    _compress(dbPath, dictionary, zstd!);

    // ל-isolate של ה-worker משתנים סטטיים משלו; בלי זה הוא מחפש את DLL התוסף.
    DbReadWorker.workerSetUpForTesting = _loadTestZstd;
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  });

  tearDown(() async {
    DbReadWorker.workerSetUpForTesting = null;
    DbReadWorker.disposeForTesting();
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // ה-handle של ה-worker ב-Windows אינו משתחרר מיד; ה-temp אינו הנבדק.
    }
  });

  test('ה-fixture דחוס: כל שורה היא מסגרת zstd', () {
    final db = sqlite3.sqlite3.open(
      path.join(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath)!,
        DatabaseConstants.databaseFileName,
      ),
      mode: sqlite3.OpenMode.readOnly,
    );
    addTearDown(db.close);
    final rows = db.select(
      "SELECT typeof(content) AS type, content FROM line_content",
    );
    expect(rows, hasLength(_lines.length));
    for (final row in rows) {
      expect(row['type'], 'blob');
      expect(isZstdFrame(row['content'] as Uint8List), isTrue);
    }
  }, skip: skip);

  test('תצוגה מקדימה וטווח שורות', () async {
    final preview = await SqliteDataProvider.instance.getBookQuickPreview(
      _title,
      15,
      categoryId: categoryId,
    );
    final range = await SqliteDataProvider.instance.getBookTextRangeFromDb(
      _title,
      startLine: 2,
      endLine: 4,
      categoryId: categoryId,
    );
    expect(mainIsolateOpens, isEmpty);
    expect(preview, _lines.sublist(5, 26).join('\n'));
    expect(range?.text, _lines.sublist(2, 5).join('\n'));
  }, skip: skip);

  test('שורות ספר-מילון (לעז)', () async {
    final lines = await loadDictionaryBookLines(_title);
    expect(mainIsolateOpens, isEmpty);
    expect(lines, _lines);
  }, skip: skip);

  test('השורה הגולמית לדיווח טעות', () async {
    final snapshot = await ErrorReportHelper.resolveReportSource(
      book: TextBook(title: _title, categoryId: categoryId),
      lineIndex: 3,
      content: _lines,
    );
    expect(mainIsolateOpens, isEmpty);
    expect(snapshot?.originalLine, _lines[3]);
  }, skip: skip);

  test('סמני חלוקה בפתיחת ספר נקראים ב-worker הקבוע', () async {
    final before = DbReadWorker.sentMessageCount;
    for (var i = 0; i < 2; i++) {
      final marks = await DatabaseLibraryProvider.instance
          .getInlineSectionMarksByLineIndex(_title, categoryId: categoryId);
      expect(marks.headings, {
        10: [_topics[10]],
      });
    }
    expect(DbReadWorker.sentMessageCount - before, 2);
    expect(mainIsolateOpens, isEmpty);
  }, skip: skip);
}

Future<int> _seedDb(String dbPath) async {
  final database = MyDatabase.withPath(dbPath);
  try {
    final repo = SeforimRepository(database);
    await repo.ensureInitialized();
    final categoryId = await repo.insertCategory(
      const migration_models.Category(title: 'שורש'),
    );
    final sourceId = await repo.insertSource('test::$_title', -1);
    final bookId = await repo.insertBook(
      migration_models.Book(
        categoryId: categoryId,
        sourceId: sourceId,
        title: _title,
        fileType: 'txt',
        totalLines: _lines.length,
      ),
    );
    await repo.insertLinesBatch([
      for (var i = 0; i < _lines.length; i++)
        migration_models.Line(bookId: bookId, lineIndex: i, content: _lines[i]),
    ]);
    await repo.updateBookTotalLines(bookId, _lines.length);

    final db = await database.database;
    db.execute(
      "INSERT INTO alt_toc_structure (id, bookId, key) VALUES (1, ?, 'Topic')",
      [bookId],
    );
    for (final MapEntry(key: lineIndex, value: label) in _topics.entries) {
      db.execute('INSERT INTO tocText (id, text) VALUES (?, ?)', [
        lineIndex,
        label,
      ]);
      db.execute(
        'INSERT INTO alt_toc_entry (structureId, textId, level, lineId) '
        'SELECT 1, ?, 1, id FROM line WHERE bookId = ? AND lineIndex = ?',
        [lineIndex, bookId, lineIndex],
      );
    }
    return categoryId;
  } finally {
    database.close();
  }
}

/// הופך את המסד לצורת סכמה 6 דחוסה: התוכן ב-line_content כמסגרות zstd.
void _compress(String dbPath, Uint8List dictionary, DynamicLibrary zstd) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute(
      'CREATE TABLE line_content (id INTEGER PRIMARY KEY NOT NULL, '
      'content TEXT NOT NULL)',
    );
    db.execute('INSERT INTO line_content SELECT id, content FROM line');
    db.execute('ALTER TABLE line DROP COLUMN content');
    db.execute('CREATE TABLE zstd_dict (id INTEGER PRIMARY KEY, dict BLOB)');
    db.execute('INSERT INTO zstd_dict VALUES (1, ?)', [dictionary]);
    for (final row in db.select('SELECT id, content FROM line_content')) {
      final frame = compressWithDictionary(
        zstd,
        Uint8List.fromList(utf8.encode(row['content'] as String)),
        dictionary,
      );
      db.execute('UPDATE line_content SET content = ? WHERE id = ?', [
        frame,
        row['id'],
      ]);
    }
  } finally {
    db.close();
  }
}
