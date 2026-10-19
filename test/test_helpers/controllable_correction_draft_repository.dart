import 'dart:async';

import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';

/// מאגר טיוטות אמיתי שאפשר לעכב או להכשיל בו כתיבות.
///
/// כל מתודה מועברת במפורש, כדי ששינוי בממשק ייכשל בקומפילציה ולא בשקט.
class ControllableCorrectionDraftRepository
    implements PluginCorrectionDraftRepository {
  ControllableCorrectionDraftRepository(this.inner);

  final PluginCorrectionDraftRepository inner;

  /// כתיבה ממתינה לו לפני שהיא מגיעה למסד.
  Completer<void>? gate;
  bool failWrites = false;
  int writeCalls = 0;

  @override
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
  }) => inner.acquire(
    pluginId: pluginId,
    draftId: draftId,
    bookUid: bookUid,
    bookId: bookId,
    bookSource: bookSource,
    libraryVersion: libraryVersion,
  );

  @override
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
    writeCalls++;
    await gate?.future;
    if (failWrites) throw StateError('כתיבה נכשלה (בדיקה)');
    return inner.write(
      pluginId: pluginId,
      draftId: draftId,
      token: token,
      revision: revision,
      libraryVersion: libraryVersion,
      changesJson: changesJson,
      conflictsJson: conflictsJson,
      expectedVersion: expectedVersion,
    );
  }

  @override
  Future<({String status, int? version})> rescue({
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
    required String entriesJson,
    required int sinceEpoch,
  }) => inner.rescue(
    pluginId: pluginId,
    draftId: draftId,
    bookUid: bookUid,
    bookId: bookId,
    bookSource: bookSource,
    libraryVersion: libraryVersion,
    entriesJson: entriesJson,
    sinceEpoch: sinceEpoch,
  );

  @override
  Future<void> release({
    required String pluginId,
    required String draftId,
    required String token,
  }) => inner.release(pluginId: pluginId, draftId: draftId, token: token);

  @override
  Future<Map<String, Object?>> acknowledge({
    required String pluginId,
    required String draftId,
    required int version,
  }) => inner.acknowledge(
    pluginId: pluginId,
    draftId: draftId,
    version: version,
  );

  @override
  Future<List<Map<String, Object?>>> list(String pluginId) =>
      inner.list(pluginId);

  @override
  Future<Map<String, Object?>?> get(String pluginId, String draftId) =>
      inner.get(pluginId, draftId);

  @override
  Future<void> purge(String pluginId) => inner.purge(pluginId);

  @override
  Future<void> heartbeat() => inner.heartbeat();

  @override
  Future<void> dispose() => inner.dispose();
}
