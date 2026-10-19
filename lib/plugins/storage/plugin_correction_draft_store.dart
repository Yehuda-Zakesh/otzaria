import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';

/// מזהה טיוטה יציב לתוסף + ספר. קידוד JSON של הזוג מונע התנגשות שרשור.
String correctionDraftId(String pluginId, String bookUid) => base64Url
    .encode(sha256.convert(utf8.encode(jsonEncode([pluginId, bookUid]))).bytes)
    .replaceAll('=', '');

/// טיוטות התיקון העמידות וה-lease שלהן. כל פעולה היא טרנזקציה אחת.
///
/// הכתיבה היא UPDATE בלבד ומותנית ב-holder, ולכן כתיבה ממתינה אינה יוצרת
/// מחדש טיוטה שנמחקה, ובעלים שאיבד את ה-lease אינו דורס בעלים חדש.
abstract final class PluginCorrectionDraftStore {
  static const String table = 'plugin_correction_draft';
  static const String counterTable = 'plugin_correction_draft_counter';
  static const String purgeTable = 'plugin_correction_draft_purge';

  static void createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        plugin_id TEXT NOT NULL,
        draft_id TEXT NOT NULL,
        book_uid TEXT NOT NULL,
        book_id TEXT NOT NULL,
        book_source TEXT NOT NULL,
        library_version TEXT NOT NULL,
        version INTEGER NOT NULL,
        changes_json TEXT NOT NULL,
        conflicts_json TEXT NOT NULL,
        acknowledged_version INTEGER,
        holder TEXT,
        holder_revision INTEGER,
        heartbeat_at INTEGER,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (plugin_id, draft_id)
      )
    ''');
    // המונה אינו נמחק עם הטיוטות, ולכן draftId + version אינו חוזר לעולם.
    db.execute('''
      CREATE TABLE IF NOT EXISTS $counterTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        value INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS $purgeTable (
        plugin_id TEXT PRIMARY KEY,
        epoch INTEGER NOT NULL
      )
    ''');
  }

  static T _transaction<T>(Database db, T Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static int _nextVersion(Database db) {
    db.execute(
      'INSERT INTO $counterTable (id, value) VALUES (1, 1) '
      'ON CONFLICT(id) DO UPDATE SET value = value + 1',
    );
    return db
            .select('SELECT value FROM $counterTable WHERE id = 1')
            .first['value']
        as int;
  }

  static bool _hasContent(Map<String, Object?> row) =>
      row['changes_json'] != '[]' || row['conflicts_json'] != '[]';

  static Map<String, Object?>? _row(
    Database db,
    String pluginId,
    String draftId,
  ) {
    final rows = db.select(
      'SELECT * FROM $table WHERE plugin_id = ? AND draft_id = ?',
      [pluginId, draftId],
    );
    return rows.isEmpty ? null : Map<String, Object?>.of(rows.first);
  }

  /// רוכש את ה-lease אם הוא פנוי או שפג תוקפו. מחזיר `acquired: false`
  /// כשבעלים אחר חי, ואחרת את תוכן הטיוטה הקיים לשחזור.
  static Map<String, Object?> acquire(
    Database db, {
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
    required String token,
    required int nowMs,
    required int ttlMs,
  }) => _transaction(db, () {
    final row = _row(db, pluginId, draftId);
    if (row != null &&
        row['holder'] != null &&
        (row['heartbeat_at'] as int? ?? 0) >= nowMs - ttlMs) {
      return {'acquired': false};
    }
    if (row == null) {
      db.execute(
        'INSERT INTO $table (plugin_id, draft_id, book_uid, book_id, '
        'book_source, library_version, version, changes_json, conflicts_json, '
        'holder, holder_revision, heartbeat_at, updated_at) '
        "VALUES (?, ?, ?, ?, ?, ?, ?, '[]', '[]', ?, 0, ?, ?)",
        [
          pluginId,
          draftId,
          bookUid,
          bookId,
          bookSource,
          libraryVersion,
          _nextVersion(db),
          token,
          nowMs,
          nowMs,
        ],
      );
      return {
        'acquired': true,
        'epoch': _nextVersion(db),
        'version': null,
        'changes': '[]',
        'conflicts': '[]',
      };
    }
    db.execute(
      'UPDATE $table SET holder = ?, holder_revision = 0, heartbeat_at = ?, '
      'book_id = ?, book_source = ? WHERE plugin_id = ? AND draft_id = ?',
      [token, nowMs, bookId, bookSource, pluginId, draftId],
    );
    return {
      'acquired': true,
      'epoch': _nextVersion(db),
      'version': _hasContent(row) ? row['version'] : null,
      'changes': row['changes_json'],
      'conflicts': row['conflicts_json'],
    };
  });

  /// שומר את המצב המלא של revision. `conflicts` מוחלף רק כשנמסר (בשחזור).
  ///
  /// `lost` — ה-lease אינו בידי [token] (או שהטיוטה נמחקה); `stale` — כבר
  /// נשמר revision חדש יותר, והכתיבה הישנה אינה דורסת אותו; `conflict` —
  /// הגרסה אינה [expectedVersion] (למשל ack בזמן שחזור).
  static Map<String, Object?> write(
    Database db, {
    required String pluginId,
    required String draftId,
    required String token,
    required int revision,
    required String libraryVersion,
    required String changesJson,
    String? conflictsJson,
    int? expectedVersion,
    required int nowMs,
  }) => _transaction(db, () {
    final row = _row(db, pluginId, draftId);
    if (row == null || row['holder'] != token) return {'status': 'lost'};
    if ((row['holder_revision'] as int? ?? 0) >= revision) {
      return {
        'status': 'stale',
        'version': row['version'],
        'conflicts': row['conflicts_json'],
      };
    }
    if (expectedVersion != null &&
        (row['version'] != expectedVersion || !_hasContent(row))) {
      return {'status': 'conflict'};
    }
    final version = _nextVersion(db);
    final conflicts = conflictsJson ?? row['conflicts_json'] as String;
    db.execute(
      'UPDATE $table SET version = ?, changes_json = ?, conflicts_json = ?, '
      'library_version = ?, holder_revision = ?, heartbeat_at = ?, '
      'updated_at = ? WHERE plugin_id = ? AND draft_id = ? AND holder = ?',
      [
        version,
        changesJson,
        conflicts,
        libraryVersion,
        revision,
        nowMs,
        nowMs,
        pluginId,
        draftId,
        token,
      ],
    );
    return {'status': 'ok', 'version': version, 'conflicts': conflicts};
  });

  static void heartbeat(Database db, Iterable<String> tokens, int nowMs) {
    final list = tokens.toList();
    if (list.isEmpty) return;
    db.execute(
      'UPDATE $table SET heartbeat_at = ? '
      'WHERE holder IN (${List.filled(list.length, '?').join(', ')})',
      [nowMs, ...list],
    );
  }

  /// משחרר את ה-lease של [token] בלבד. שורה ריקה שלא אושרה נמחקת.
  static void release(
    Database db, {
    required String pluginId,
    required String draftId,
    required String token,
  }) => _transaction(db, () {
    db.execute(
      "DELETE FROM $table WHERE plugin_id = ? AND draft_id = ? AND holder = ? "
      "AND changes_json = '[]' AND conflicts_json = '[]' "
      'AND acknowledged_version IS NULL',
      [pluginId, draftId, token],
    );
    db.execute(
      'UPDATE $table SET holder = NULL, heartbeat_at = NULL '
      'WHERE plugin_id = ? AND draft_id = ? AND holder = ?',
      [pluginId, draftId, token],
    );
  });

  /// מנקה את התוכן רק אם [version] היא הגרסה הנוכחית; אישור ישן אינו
  /// מוחק שינוי חדש יותר.
  static Map<String, Object?> acknowledge(
    Database db, {
    required String pluginId,
    required String draftId,
    required int version,
    required int nowMs,
  }) => _transaction(db, () {
    final row = _row(db, pluginId, draftId);
    if (row == null) return {'status': 'not_found'};
    if (row['version'] == version && _hasContent(row)) {
      db.execute(
        "UPDATE $table SET changes_json = '[]', conflicts_json = '[]', "
        'acknowledged_version = ?, updated_at = ? '
        'WHERE plugin_id = ? AND draft_id = ? AND version = ?',
        [version, nowMs, pluginId, draftId, version],
      );
      return {'status': 'acknowledged'};
    }
    if (row['acknowledged_version'] == version) return {'status': 'duplicate'};
    return {
      'status': 'conflict',
      'currentVersion': _hasContent(row) ? row['version'] : null,
    };
  });

  static Map<String, Object?> _public(
    Map<String, Object?> row,
    int nowMs,
    int ttlMs, {
    required bool content,
  }) => {
    'draftId': row['draft_id'],
    'bookId': row['book_id'],
    'bookUid': row['book_uid'],
    'bookSource': row['book_source'],
    'libraryVersion': row['library_version'],
    'version': row['version'],
    'updatedAt': DateTime.fromMillisecondsSinceEpoch(
      row['updated_at'] as int,
      isUtc: true,
    ).toIso8601String(),
    'active':
        row['holder'] != null &&
        (row['heartbeat_at'] as int? ?? 0) >= nowMs - ttlMs,
    if (content) ...{
      'changes': jsonDecode(row['changes_json'] as String),
      'conflicts': jsonDecode(row['conflicts_json'] as String),
    } else ...{
      'changeCount': (jsonDecode(row['changes_json'] as String) as List).length,
      'conflictCount':
          (jsonDecode(row['conflicts_json'] as String) as List).length,
    },
  };

  /// טיוטות עם תוכן שלא אושר, ללא התוכן עצמו.
  static List<Map<String, Object?>> list(
    Database db,
    String pluginId,
    int nowMs,
    int ttlMs,
  ) => [
    for (final row in db.select(
      "SELECT * FROM $table WHERE plugin_id = ? AND "
      "(changes_json != '[]' OR conflicts_json != '[]') ORDER BY updated_at DESC",
      [pluginId],
    ))
      _public(Map.of(row), nowMs, ttlMs, content: false),
  ];

  static Map<String, Object?>? get(
    Database db,
    String pluginId,
    String draftId,
    int nowMs,
    int ttlMs,
  ) {
    final row = _row(db, pluginId, draftId);
    if (row == null || !_hasContent(row)) return null;
    return _public(row, nowMs, ttlMs, content: true);
  }

  /// הסימון נשאר אחרי המחיקה, כדי שהצלה מסשן שנפתח לפני המחיקה לא תחזיר אותה.
  static void purge(Database db, String pluginId) => _transaction(db, () {
    db.execute('DELETE FROM $table WHERE plugin_id = ?', [pluginId]);
    db.execute(
      'INSERT INTO $purgeTable (plugin_id, epoch) VALUES (?, ?) '
      'ON CONFLICT(plugin_id) DO UPDATE SET epoch = excluded.epoch',
      [pluginId, _nextVersion(db)],
    );
  });

  /// מצב שלא נשמר של בעלים שאיבד את ה-lease נוסף כהתנגשויות בלבד: אינו נוגע
  /// ב-changes או ב-holder של הבעלים החדש, ואינו מחזיר טיוטה שנמחקה אחרי [sinceEpoch].
  static Map<String, Object?> rescue(
    Database db, {
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
    required String entriesJson,
    required int sinceEpoch,
    required int nowMs,
  }) => _transaction(db, () {
    final purged = db.select(
      'SELECT epoch FROM $purgeTable WHERE plugin_id = ?',
      [pluginId],
    );
    if (purged.isNotEmpty && (purged.first['epoch'] as int) > sinceEpoch) {
      return {'status': 'purged'};
    }
    final row = _row(db, pluginId, draftId);
    final conflicts = [
      for (final value
          in jsonDecode(row?['conflicts_json'] as String? ?? '[]') as List)
        Map<String, Object?>.from(value as Map),
    ];
    String key(Map<String, Object?> entry) => jsonEncode([
      entry['sectionIndex'],
      entry['originalSourceText'],
      entry['proposedText'],
    ]);
    final known = {
      for (final conflict in conflicts) key(conflict),
      for (final value
          in jsonDecode(row?['changes_json'] as String? ?? '[]') as List)
        key(Map<String, Object?>.from(value as Map)),
    };
    var added = false;
    for (final value in jsonDecode(entriesJson) as List) {
      final entry = Map<String, Object?>.from(value as Map);
      if (known.add(key(entry))) {
        conflicts.add(entry);
        added = true;
      }
    }
    if (!added) return {'status': 'ok', 'version': row?['version']};
    final version = _nextVersion(db);
    if (row == null) {
      db.execute(
        'INSERT INTO $table (plugin_id, draft_id, book_uid, book_id, '
        'book_source, library_version, version, changes_json, conflicts_json, '
        "updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, '[]', ?, ?)",
        [
          pluginId,
          draftId,
          bookUid,
          bookId,
          bookSource,
          libraryVersion,
          version,
          jsonEncode(conflicts),
          nowMs,
        ],
      );
    } else {
      db.execute(
        'UPDATE $table SET version = ?, conflicts_json = ?, updated_at = ? '
        'WHERE plugin_id = ? AND draft_id = ?',
        [version, jsonEncode(conflicts), nowMs, pluginId, draftId],
      );
    }
    return {'status': 'ok', 'version': version};
  });
}
