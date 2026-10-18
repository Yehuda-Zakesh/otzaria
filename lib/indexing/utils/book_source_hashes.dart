import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:sqlite3/sqlite3.dart';

/// חותם התוכן שהמסד מחזיק לכל ספר (`book.contentHash`, סכמה 7) — נצרב באינדקס
/// כ-sourceHash ומושווה אליו כדי לגלות שינוי בלי לקרוא את טקסט הספר.
class BookSourceHashes {
  BookSourceHashes(this._official, this._attached);

  static final BookSourceHashes none = BookSourceHashes(const {}, const {});

  final Map<int, BigInt>? _official;
  final Map<String, Map<int, BigInt>?> _attached;

  /// null כשהמסד אינו מחזיק חותם לספר (מסד ישן, ספר אישי, או 0 = לא ידוע).
  BigInt? forSource(BookSource source, int id) {
    final hashes = switch (source) {
      OfficialBookSource() => _official,
      AttachedBookSource(:final slug) => _attached[slug],
      UserBookSource() => null,
    };
    final hash = hashes?[id];
    return hash == null || hash == BigInt.zero ? null : hash;
  }

  /// האם למסד של [source] יש עמודת חותם — אחרת אין טעם לחפש בו.
  bool covers(BookSource source) => switch (source) {
    OfficialBookSource() => _official != null,
    AttachedBookSource(:final slug) => _attached[slug] != null,
    UserBookSource() => false,
  };

  /// קורא את החותמים מ-seforim.db ומהמסדים המצורפים ב-[attachedSlugs].
  static Future<BookSourceHashes> load({
    Iterable<String> attachedSlugs = const [],
  }) async {
    final official = await _read(SqliteDataProvider.instance.repository);
    final attached = <String, Map<int, BigInt>?>{};
    for (final slug in attachedSlugs.toSet()) {
      try {
        attached[slug] = await _read(
          await AttachedLibraryRegistry.instance.repositoryFor(slug),
        );
      } catch (e) {
        debugPrint('⚠️ פתיחת המסד המצורף $slug לחותמי תוכן נכשלה: $e');
      }
    }
    return BookSourceHashes(official, attached);
  }

  static Future<Map<int, BigInt>?> _read(SeforimRepository? repository) async {
    if (repository == null) return null;
    try {
      final capabilities = await repository.database.capabilities;
      if (!capabilities.hasColumn('book', 'contentHash')) return null;
      // כל טבלת book: עשרות ms (נמדד 34ms ב-7,766 ספרים) — מחוץ ל-UI isolate.
      final path = repository.database.path;
      final rows = await Isolate.run(() => _readRows(path));
      return {
        for (final (id, hash) in rows) id: toUnsigned(hash),
      };
    } catch (e) {
      debugPrint('⚠️ קריאת חותמי התוכן מהמסד נכשלה: $e');
      return null;
    }
  }

  static List<(int, int)> _readRows(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return [
        for (final row in db.select('SELECT id, contentHash FROM book'))
          (row['id'] as int, row['contentHash'] as int),
      ];
    } finally {
      db.close();
    }
  }

  /// SQLite שומר את החותם כ-i64; המנוע מקבל u64 — אותה המרה בשני הכיוונים.
  @visibleForTesting
  static BigInt toUnsigned(int value) => BigInt.from(value).toUnsigned(64);
}
