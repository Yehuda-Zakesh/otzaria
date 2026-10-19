import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';

/// ה-lease נתפס אצל בעלים חי אחר (לשונית או חלון אחר).
class PluginCorrectionDraftBusy implements Exception {
  const PluginCorrectionDraftBusy();
}

/// גישה לטיוטות התיקון העמידות שב-`plugins_host.db`.
///
/// בייצור כל פעולה רצה ב-isolate נפרד עם חיבור משלו: SQLite סינכרוני, ונעילה
/// של חלון אחר הייתה חוסמת את ה-UI עד `busy_timeout` בכל הקשה.
class PluginCorrectionDraftRepository {
  static const Duration leaseTtl = Duration(seconds: 20);
  static const Duration heartbeatInterval = Duration(seconds: 5);

  final _Backend _backend;

  PluginCorrectionDraftRepository._(this._backend);

  /// ה-worker נוצר בבקשה הראשונה, לא באתחול האפליקציה.
  factory PluginCorrectionDraftRepository.isolate({
    Future<String> Function()? dbPath,
  }) => PluginCorrectionDraftRepository._(
    _IsolateBackend(dbPath ?? AppPaths.resolvePluginsDbPath),
  );

  /// אותו SQL על חיבור קיים, ללא isolate וללא heartbeat אוטומטי.
  @visibleForTesting
  factory PluginCorrectionDraftRepository.direct(
    Database db, {
    int Function()? nowMs,
    Duration ttl = leaseTtl,
  }) {
    PluginCorrectionDraftStore.createSchema(db);
    return PluginCorrectionDraftRepository._(
      _DirectBackend(
        db,
        nowMs ?? () => DateTime.now().millisecondsSinceEpoch,
        ttl,
      ),
    );
  }

  /// מחזיר את ה-token ואת תוכן הטיוטה הקיים, או זורק [PluginCorrectionDraftBusy].
  /// [epoch] מסמן את רגע הרכישה מול מחיקות מכוונות (ראו [rescue]).
  Future<
    ({String token, int epoch, int? version, String changes, String conflicts})
  >
  acquire({
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
  }) async {
    final result = await _backend.call('acquire', {
      'pluginId': pluginId,
      'draftId': draftId,
      'bookUid': bookUid,
      'bookId': bookId,
      'bookSource': bookSource,
      'libraryVersion': libraryVersion,
    });
    if (result['acquired'] != true) throw const PluginCorrectionDraftBusy();
    return (
      token: result['token'] as String,
      epoch: result['epoch'] as int,
      version: result['version'] as int?,
      changes: result['changes'] as String,
      conflicts: result['conflicts'] as String,
    );
  }

  Future<({String status, int? version, String? conflicts})> write({
    required String pluginId,
    required String draftId,
    required String token,
    required int revision,
    required String libraryVersion,
    required String changesJson,
    String? conflictsJson,
    int? expectedVersion,
  }) async {
    final result = await _backend.call('write', {
      'pluginId': pluginId,
      'draftId': draftId,
      'token': token,
      'revision': revision,
      'libraryVersion': libraryVersion,
      'changesJson': changesJson,
      'conflictsJson': conflictsJson,
      'expectedVersion': expectedVersion,
    });
    return (
      status: result['status'] as String,
      version: result['version'] as int?,
      conflicts: result['conflicts'] as String?,
    );
  }

  /// שומר מצב של בעלים שאיבד את ה-lease כהתנגשויות בטיוטה, בלי לדרוס את
  /// הבעלים החדש. `purged` — הטיוטה נמחקה באישור המשתמש אחרי [sinceEpoch].
  Future<({String status, int? version})> rescue({
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
    required String entriesJson,
    required int sinceEpoch,
  }) async {
    final result = await _backend.call('rescue', {
      'pluginId': pluginId,
      'draftId': draftId,
      'bookUid': bookUid,
      'bookId': bookId,
      'bookSource': bookSource,
      'libraryVersion': libraryVersion,
      'entriesJson': entriesJson,
      'sinceEpoch': sinceEpoch,
    });
    return (
      status: result['status'] as String,
      version: result['version'] as int?,
    );
  }

  Future<void> release({
    required String pluginId,
    required String draftId,
    required String token,
  }) => _backend.call('release', {
    'pluginId': pluginId,
    'draftId': draftId,
    'token': token,
  });

  /// `acknowledged`, `duplicate`, `conflict` (עם `currentVersion`) או `not_found`.
  Future<Map<String, Object?>> acknowledge({
    required String pluginId,
    required String draftId,
    required int version,
  }) => _backend.call('acknowledge', {
    'pluginId': pluginId,
    'draftId': draftId,
    'version': version,
  });

  Future<List<Map<String, Object?>>> list(String pluginId) async =>
      ((await _backend.call('list', {'pluginId': pluginId}))['drafts'] as List)
          .cast<Map<String, Object?>>();

  Future<Map<String, Object?>?> get(String pluginId, String draftId) async =>
      (await _backend.call('get', {
            'pluginId': pluginId,
            'draftId': draftId,
          }))['draft']
          as Map<String, Object?>?;

  Future<void> purge(String pluginId) =>
      _backend.call('purge', {'pluginId': pluginId});

  /// ריענון ה-lease של token שנרכש. ב-isolate הוא אוטומטי.
  @visibleForTesting
  Future<void> heartbeat() => _backend.call('heartbeat', const {});

  Future<void> dispose() => _backend.dispose();
}

abstract class _Backend {
  Future<Map<String, Object?>> call(String op, Map<String, Object?> args);
  Future<void> dispose();
}

/// מבצע פעולה על חיבור; משותף ל-isolate ולמימוש הישיר.
class _Executor {
  final Database db;
  final int Function() nowMs;
  final int ttlMs;
  final Set<String> heldTokens = {};
  final Random _random = Random.secure();

  _Executor(this.db, this.nowMs, this.ttlMs);

  Map<String, Object?> run(String op, Map<String, Object?> a) {
    switch (op) {
      case 'acquire':
        final token = base64UrlEncode(
          List<int>.generate(18, (_) => _random.nextInt(256)),
        );
        final result = PluginCorrectionDraftStore.acquire(
          db,
          pluginId: a['pluginId'] as String,
          draftId: a['draftId'] as String,
          bookUid: a['bookUid'] as String,
          bookId: a['bookId'] as String,
          bookSource: a['bookSource'] as String,
          libraryVersion: a['libraryVersion'] as String,
          token: token,
          nowMs: nowMs(),
          ttlMs: ttlMs,
        );
        if (result['acquired'] == true) heldTokens.add(token);
        return {...result, 'token': token};
      case 'write':
        final result = PluginCorrectionDraftStore.write(
          db,
          pluginId: a['pluginId'] as String,
          draftId: a['draftId'] as String,
          token: a['token'] as String,
          revision: a['revision'] as int,
          libraryVersion: a['libraryVersion'] as String,
          changesJson: a['changesJson'] as String,
          conflictsJson: a['conflictsJson'] as String?,
          expectedVersion: a['expectedVersion'] as int?,
          nowMs: nowMs(),
        );
        // worker שעלה מחדש לומד מהכתיבה אילו leases בידיו, כדי לחדש אותם.
        if (result['status'] == 'lost') {
          heldTokens.remove(a['token']);
        } else {
          heldTokens.add(a['token'] as String);
        }
        return result;
      case 'release':
        heldTokens.remove(a['token']);
        PluginCorrectionDraftStore.release(
          db,
          pluginId: a['pluginId'] as String,
          draftId: a['draftId'] as String,
          token: a['token'] as String,
        );
        return const {};
      case 'acknowledge':
        return PluginCorrectionDraftStore.acknowledge(
          db,
          pluginId: a['pluginId'] as String,
          draftId: a['draftId'] as String,
          version: a['version'] as int,
          nowMs: nowMs(),
        );
      case 'list':
        return {
          'drafts': PluginCorrectionDraftStore.list(
            db,
            a['pluginId'] as String,
            nowMs(),
            ttlMs,
          ),
        };
      case 'get':
        return {
          'draft': PluginCorrectionDraftStore.get(
            db,
            a['pluginId'] as String,
            a['draftId'] as String,
            nowMs(),
            ttlMs,
          ),
        };
      case 'purge':
        PluginCorrectionDraftStore.purge(db, a['pluginId'] as String);
        return const {};
      case 'rescue':
        return PluginCorrectionDraftStore.rescue(
          db,
          pluginId: a['pluginId'] as String,
          draftId: a['draftId'] as String,
          bookUid: a['bookUid'] as String,
          bookId: a['bookId'] as String,
          bookSource: a['bookSource'] as String,
          libraryVersion: a['libraryVersion'] as String,
          entriesJson: a['entriesJson'] as String,
          sinceEpoch: a['sinceEpoch'] as int,
          nowMs: nowMs(),
        );
      case 'heartbeat':
        PluginCorrectionDraftStore.heartbeat(db, heldTokens, nowMs());
        return const {};
    }
    throw ArgumentError.value(op, 'op');
  }
}

class _DirectBackend implements _Backend {
  final _Executor _executor;

  _DirectBackend(Database db, int Function() nowMs, Duration ttl)
    : _executor = _Executor(db, nowMs, ttl.inMilliseconds);

  @override
  Future<Map<String, Object?>> call(String op, Map<String, Object?> args) =>
      Future(() => _executor.run(op, args));

  @override
  Future<void> dispose() async {}
}

class _IsolateBackend implements _Backend {
  final Future<String> Function() _dbPath;
  Future<SendPort>? _commandPort;
  final ReceivePort _replies = ReceivePort();
  final ReceivePort _exit = ReceivePort();
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  int _nextId = 0;

  Completer<void>? _exited;

  _IsolateBackend(this._dbPath) {
    _replies.listen(_onReply);
    _exit.listen((_) {
      _exited?.complete();
      _exited = null;
      _failAll(StateError('correction draft worker exited'));
    });
  }

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    _readyCompleter = ready;
    await Isolate.spawn<List<Object>>(
      _workerMain,
      [_replies.sendPort, await _dbPath()],
      debugName: 'PluginCorrectionDrafts',
      onExit: _exit.sendPort,
      errorsAreFatal: false,
    );
    return ready.future;
  }

  Completer<SendPort>? _readyCompleter;

  void _onReply(Object? message) {
    if (message is SendPort) {
      _readyCompleter?.complete(message);
      return;
    }
    final reply = (message as Map).cast<String, Object?>();
    if (reply.containsKey('fatal')) {
      _failAll(StateError('correction draft worker failed: ${reply['fatal']}'));
      return;
    }
    final completer = _pending.remove(reply['id']);
    if (completer == null) return;
    if (reply.containsKey('error')) {
      completer.completeError(StateError(reply['error'] as String));
    } else {
      completer.complete((reply['result'] as Map).cast<String, Object?>());
    }
  }

  void _failAll(Object error) {
    // worker שיצא לפני שעלה (פתיחת המסד נכשלה) — אחרת כל קריאה נתקעת.
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    _commandPort = null;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }

  @override
  Future<Map<String, Object?>> call(
    String op,
    Map<String, Object?> args,
  ) async {
    final port = await (_commandPort ??= _start().catchError((Object error) {
      _commandPort = null;
      throw error;
    }));
    final id = _nextId++;
    final completer = _pending[id] = Completer<Map<String, Object?>>();
    port.send({'id': id, 'op': op, 'args': args});
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    SendPort? port;
    try {
      port = await _commandPort;
    } catch (_) {}
    if (port != null) {
      // ממתינים לסגירת החיבור, כדי שהקובץ לא יישאר נעול אחרי dispose.
      final exited = _exited = Completer<void>();
      port.send(null);
      await exited.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    _commandPort = null;
    _replies.close();
    _exit.close();
  }
}

/// ה-worker: חיבור משלו, טרנזקציה לכל בקשה ו-heartbeat ל-leases שבידיו.
void _workerMain(List<Object> init) {
  final replies = init[0] as SendPort;
  final Database db;
  try {
    db = openWritableDatabase(init[1] as String, 'PluginCorrectionDrafts');
    PluginCorrectionDraftStore.createSchema(db);
  } catch (error) {
    replies.send({'fatal': '$error'});
    return;
  }
  final executor = _Executor(
    db,
    () => DateTime.now().millisecondsSinceEpoch,
    PluginCorrectionDraftRepository.leaseTtl.inMilliseconds,
  );
  final commands = ReceivePort();
  final heartbeat = Timer.periodic(
    PluginCorrectionDraftRepository.heartbeatInterval,
    (_) {
      try {
        executor.run('heartbeat', const {});
      } catch (error) {
        debugPrint('[PluginCorrectionDrafts] heartbeat failed: $error');
      }
    },
  );
  commands.listen((message) {
    if (message == null) {
      heartbeat.cancel();
      commands.close();
      closeWithCheckpoint(db);
      return;
    }
    final request = (message as Map).cast<String, Object?>();
    try {
      replies.send({
        'id': request['id'],
        'result': executor.run(
          request['op'] as String,
          (request['args'] as Map).cast<String, Object?>(),
        ),
      });
    } catch (error) {
      replies.send({'id': request['id'], 'error': '$error'});
    }
  });
  replies.send(commands.sendPort);
}
