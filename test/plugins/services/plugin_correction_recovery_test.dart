import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';
import 'package:path/path.dart' as p;

typedef _WriteResult = ({String status, int? version, String? conflicts});

/// עוטף מאגר אמיתי: מעכב כתיבות לפני שהן מגיעות ל-SQLite, מכשיל אותן ומתעד.
class _ControlledRepository implements PluginCorrectionDraftRepository {
  _ControlledRepository(this.inner);

  final PluginCorrectionDraftRepository inner;
  Completer<void>? gate;
  Completer<void>? acquireGate;
  int failWrites = 0;
  int failRescues = 0;
  int rescues = 0;

  /// הכתיבה נשמרת ב-SQLite אבל התשובה אובדת (כמו worker שקרס אחרי commit).
  int loseReplies = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  final attempts = <int>[];
  final committed = <({int revision, String status})>[];

  @override
  Future<_WriteResult> write({
    required String pluginId,
    required String draftId,
    required String token,
    required int revision,
    required String libraryVersion,
    required String changesJson,
    String? conflictsJson,
    int? expectedVersion,
  }) async {
    attempts.add(revision);
    inFlight++;
    maxInFlight = max(maxInFlight, inFlight);
    try {
      final blocked = gate;
      if (blocked != null) await blocked.future;
      if (failWrites > 0) {
        failWrites--;
        throw StateError('disk full');
      }
      final result = await inner.write(
        pluginId: pluginId,
        draftId: draftId,
        token: token,
        revision: revision,
        libraryVersion: libraryVersion,
        changesJson: changesJson,
        conflictsJson: conflictsJson,
        expectedVersion: expectedVersion,
      );
      committed.add((revision: revision, status: result.status));
      if (loseReplies > 0) {
        loseReplies--;
        throw StateError('correction draft worker exited');
      }
      return result;
    } finally {
      inFlight--;
    }
  }

  void open() {
    final blocked = gate;
    gate = null;
    if (blocked != null && !blocked.isCompleted) blocked.complete();
  }

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
  }) async {
    final blocked = acquireGate;
    if (blocked != null) await blocked.future;
    return inner.acquire(
      pluginId: pluginId,
      draftId: draftId,
      bookUid: bookUid,
      bookId: bookId,
      bookSource: bookSource,
      libraryVersion: libraryVersion,
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
  }) async {
    rescues++;
    if (failRescues > 0) {
      failRescues--;
      throw StateError('disk full');
    }
    return inner.rescue(
      pluginId: pluginId,
      draftId: draftId,
      bookUid: bookUid,
      bookId: bookId,
      bookSource: bookSource,
      libraryVersion: libraryVersion,
      entriesJson: entriesJson,
      sinceEpoch: sinceEpoch,
    );
  }

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

Future<void> _idle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Matcher _error(String code) => throwsA(
  isA<PluginCorrectionException>().having((e) => e.code, 'code', code),
);

typedef _Event = (String, Map<String, dynamic>);

List<int> _indices(Map<String, dynamic> snapshot) => [
  for (final change in snapshot['changes'] as List) change['sectionIndex'],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final draftId = correctionDraftId('p', 'id:42');
  final defaultWriteInterval = PluginCorrectionSessionService.writeInterval;
  final defaultEventWindow = PluginCorrectionSessionService.eventWindow;
  final defaultFlushTimeout = PluginCorrectionSessionService.flushTimeout;
  final ttl = PluginCorrectionDraftRepository.leaseTtl.inMilliseconds;

  late Directory temp;
  late String dbPath;
  final opened = <Database>[];
  final services = <PluginCorrectionSessionService>[];
  final controlled = <_ControlledRepository>[];
  var now = 1000000;

  /// חיבור נפרד לאותו קובץ — כמו חלון או הפעלה אחרים של האפליקציה.
  PluginCorrectionDraftRepository connection() {
    final db = openWritableDatabase(dbPath, 't');
    opened.add(db);
    return PluginCorrectionDraftRepository.direct(db, nowMs: () => now);
  }

  _ControlledRepository controlledConnection() {
    final repository = _ControlledRepository(connection());
    controlled.add(repository);
    return repository;
  }

  PluginCorrectionSessionService newService(
    PluginCorrectionDraftRepository repository,
  ) {
    final service = PluginCorrectionSessionService()
      ..draftRepository = repository;
    services.add(service);
    return service;
  }

  void closeConnections() {
    for (final db in opened) {
      db.close();
    }
    opened.clear();
  }

  Future<String> original(int index) async => 'מקור $index';

  Future<Map<String, dynamic>> begin(
    PluginCorrectionSessionService service, {
    String tabId = 'tab',
    String owner = 'p',
    String bookUid = 'id:42',
    String libraryVersion = 'v1',
    Future<String> Function(int)? loadSource,
    Future<void> Function()? validateSource,
    List<_Event>? events,
  }) => service.begin(
    owner: owner,
    tabId: tabId,
    bookId: 'ספר',
    bookUid: bookUid,
    libraryVersion: libraryVersion,
    loadSource: loadSource ?? original,
    validateSource: validateSource,
    onEvent: events == null
        ? null
        : (topic, payload) => events.add((topic, payload)),
  );

  Future<Map<String, dynamic>> get(
    PluginCorrectionSessionService service,
    Map<String, dynamic> session,
  ) => service.get('p', session['sessionId']);

  void edit(
    PluginCorrectionSessionService service,
    int index,
    String proposed, {
    String tabId = 'tab',
  }) => service.editParagraph(tabId, index, 'מקור $index', proposed);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('correction-recovery-');
    dbPath = p.join(temp.path, 'plugins_host.db');
    now = 1000000;
  });

  tearDown(() async {
    for (final repository in controlled) {
      repository
        ..failWrites = 0
        ..failRescues = 0
        ..open();
      final acquireGate = repository.acquireGate;
      if (acquireGate != null && !acquireGate.isCompleted) {
        acquireGate.complete();
      }
    }
    for (final service in services) {
      service.endAll('test');
      await service.flushAll(timeout: const Duration(seconds: 1));
    }
    await _idle();
    services.clear();
    controlled.clear();
    closeConnections();
    PluginCorrectionSessionService.writeInterval = defaultWriteInterval;
    PluginCorrectionSessionService.eventWindow = defaultEventWindow;
    PluginCorrectionSessionService.flushTimeout = defaultFlushTimeout;
    await temp.delete(recursive: true);
  });

  group('שמירה ושחזור', () {
    test(
      'עריכה נשמרת, ואחרי סיום ללא צרכן אירועים והפעלה מחדש משוחזרת',
      () async {
        final first = newService(connection());
        final session = await begin(first);
        expect(session['recovery'], isNull);
        edit(first, 0, 'תיקון 0');
        edit(first, 3, 'תיקון 3');
        final saved = await get(first, session);
        expect(saved['draft']['persisted'], isTrue);
        expect(saved['draft']['pending'], isFalse);
        expect(saved['draft']['error'], isNull);
        expect(saved['draft']['draftId'], draftId);
        expect(saved['draft']['version'], isA<int>());
        expect(
          first.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.saved,
        );
        await first.end('p', session['sessionId'], saved['revision'] as int);

        // "הפעלה מחדש": שירות חדש וחיבור חדש לאותו קובץ. זו אינה קריסת תהליך
        // אמיתית — הסשן הקודם הסתיים ושחרר את ה-lease.
        closeConnections();
        final restarted = newService(connection());
        final recovered = await begin(restarted, tabId: 'new-tab');
        expect(recovered['recovery'], {
          'draftId': draftId,
          'fromVersion': saved['draft']['version'],
          'restoredSectionIndices': [0, 3],
          'conflicts': <Object>[],
        });
        expect(_indices(recovered), [0, 3]);
        expect(recovered['revision'], 1);
        expect(recovered['draft']['persisted'], isTrue);
        expect(
          recovered['draft']['version'],
          greaterThan(saved['draft']['version'] as int),
        );
        expect(restarted.displayText('new-tab', 3, 'מקור 3'), 'תיקון 3');
        expect(restarted.displayText('new-tab', 1, 'מקור 1'), 'מקור 1');
      },
    );

    test(
      'שינוי שנשמר שורד "קריסה"; שינוי שטרם הגיע ל-SQLite אינו משוחזר',
      () async {
        final repository = controlledConnection();
        final crashed = newService(repository);
        final session = await begin(crashed);
        edit(crashed, 0, 'נשמר');
        final committed = await get(crashed, session);
        expect(committed['draft']['persisted'], isTrue);

        // הכתיבה הבאה נעצרת לפני SQLite ולא תושלם: כך נראה תהליך שמת
        // בין ההקלדה לבין ה-commit. השירות לא מסתיים ולא משחרר את ה-lease.
        repository.gate = Completer<void>();
        edit(crashed, 1, 'לא נשמר');
        expect(
          await crashed.unpersistedTabIds([
            'tab',
          ], timeout: const Duration(milliseconds: 50)),
          {'tab'},
        );
        expect(repository.inFlight, 1);

        // בלי heartbeat ה-lease פג, ותהליך חדש משחזר את מה שנשמר בלבד.
        now += ttl + 1;
        final restarted = newService(connection());
        final recovered = await begin(restarted, tabId: 'after-crash');
        expect(recovered['recovery']['restoredSectionIndices'], [0]);
        expect(
          recovered['recovery']['fromVersion'],
          committed['draft']['version'],
        );
        expect(
          (recovered['changes'] as List).single['proposedText'],
          'נשמר',
        );

        // הכתיבה התקועה מגיעה אחרי שהבעלים התחלף — ואינה דורסת אותו, אבל
        // המצב שלה נשמר כהתנגשות displaced. בקריסה אמיתית אין כתיבה מאוחרת.
        repository.open();
        await _idle();
        expect(repository.committed.last, (revision: 2, status: 'lost'));
        expect(crashed.hasSessionForTab('tab'), isFalse);
        final draft = await restarted.getDraft('p', draftId);
        expect((draft['changes'] as List).single['proposedText'], 'נשמר');
        expect(
          [
            for (final conflict in draft['conflicts'] as List)
              (conflict['proposedText'], conflict['reason']),
          ],
          [('לא נשמר', 'displaced')],
        );
      },
    );

    test('reset וחזרה לנוסח המקור נשמרים ואינם חוזרים בשחזור', () async {
      final first = newService(connection());
      final session = await begin(first);
      edit(first, 0, 'א');
      edit(first, 1, 'ב');
      edit(first, 2, 'ג');
      await get(first, session);
      first.reset('p', session['sessionId'], 0, 3);
      edit(first, 1, 'מקור 1');
      final latest = await get(first, session);
      expect(_indices(latest), [2]);
      expect(latest['draft']['persisted'], isTrue);
      final stored = await first.getDraft('p', draftId);
      expect(
        [
          for (final change in stored['changes'] as List)
            change['sectionIndex'],
        ],
        [2],
      );
      await first.end('p', session['sessionId'], latest['revision'] as int);

      final second = newService(connection());
      final recovered = await begin(second);
      expect(recovered['recovery']['restoredSectionIndices'], [2]);
      expect(second.displayText('tab', 0, 'מקור 0'), 'מקור 0');
      expect(second.displayText('tab', 1, 'מקור 1'), 'מקור 1');

      second.reset('p', recovered['sessionId'], 2, 1);
      final empty = await get(second, recovered);
      expect(empty['draft']['persisted'], isTrue);
      await expectLater(
        second.getDraft('p', draftId),
        _error('error.not_found'),
      );
      expect(await second.listDrafts('p'), isEmpty);
      await second.end('p', recovered['sessionId'], 2);
      final third = await begin(second);
      expect(third['recovery'], isNull);
      expect(third['changes'], isEmpty);
    });

    test('שחזור חלקי: התנגשויות נשמרות לאורך עריכות, reset ו-get', () async {
      final first = newService(connection());
      final session = await begin(first);
      for (var i = 0; i < 4; i++) {
        edit(first, i, 'תיקון $i');
      }
      final saved = await first.end('p', session['sessionId'], 4);
      expect(saved['draft']['persisted'], isTrue);

      Future<String> changedSource(int index) async => switch (index) {
        1 => 'מקור שהשתנה',
        2 => throw const PluginCorrectionException(
          'error.not_found',
          'הפסקה אינה קיימת',
        ),
        3 => throw const PluginCorrectionException(
          'error.unsupported_context',
          'הפסקה אינה נתמכת',
        ),
        _ => 'מקור $index',
      };

      final second = newService(connection());
      final recovered = await begin(second, loadSource: changedSource);
      final recovery = recovered['recovery'] as Map;
      expect(recovery['fromVersion'], saved['draft']['version']);
      expect(recovery['restoredSectionIndices'], [0]);
      final conflicts = recovery['conflicts'] as List;
      expect(
        {
          for (final conflict in conflicts)
            conflict['sectionIndex']: conflict['reason'],
        },
        {1: 'source_changed', 2: 'not_found', 3: 'invalid'},
      );
      expect(conflicts.first, {
        'sectionIndex': 1,
        'originalSourceText': 'מקור 1',
        'originalText': 'מקור 1',
        'proposedText': 'תיקון 1',
        'reason': 'source_changed',
      });
      expect(recovered['draft']['conflicts'], conflicts);
      expect(_indices(recovered), [0]);

      edit(second, 0, 'תיקון 0 מעודכן');
      final edited = await get(second, recovered);
      expect(edited['draft']['persisted'], isTrue);
      expect(edited['draft']['conflicts'], conflicts);
      second.reset('p', recovered['sessionId'], 0, 2);
      final reset = await get(second, recovered);
      expect(reset['changes'], isEmpty);
      expect(reset['draft']['conflicts'], conflicts);
      final stored = await second.getDraft('p', draftId);
      expect(stored['changes'], isEmpty);
      expect(stored['conflicts'], conflicts);
      expect(
        (await second.listDrafts('p')).single,
        containsPair('conflictCount', 3),
      );
      final ended = await second.end('p', recovered['sessionId'], 3);

      final third = newService(connection());
      final again = await begin(third, loadSource: changedSource);
      expect(again['recovery']['fromVersion'], ended['draft']['version']);
      expect(again['recovery']['restoredSectionIndices'], isEmpty);
      expect(again['recovery']['conflicts'], conflicts);

      final version = again['draft']['version'] as int;
      expect(
        await third.acknowledge('p', draftId, version),
        containsPair('acknowledged', true),
      );
      expect((await get(third, again))['draft']['conflicts'], isEmpty);
      await expectLater(
        third.getDraft('p', draftId),
        _error('error.not_found'),
      );
      await third.end('p', again['sessionId'], 1);
      expect(
        (await begin(third, loadSource: changedSource))['recovery'],
        isNull,
      );
    });

    test('גרסת ספרייה חדשה עם מקור זהה עדיין משוחזרת', () async {
      final first = newService(connection());
      final session = await begin(first);
      edit(first, 0, 'תיקון');
      await first.end('p', session['sessionId'], 1);

      final second = newService(connection());
      final recovered = await begin(second, libraryVersion: 'v2');
      expect(recovered['recovery']['restoredSectionIndices'], [0]);
      expect(recovered['libraryVersion'], 'v2');
      expect((await second.getDraft('p', draftId))['libraryVersion'], 'v2');
    });
  });

  group('אישור (ack)', () {
    late PluginCorrectionSessionService service;
    late Map<String, dynamic> session;

    setUp(() async {
      service = newService(connection());
      session = await begin(service);
    });

    test('ack ישן אחרי כתיבה חדשה נדחה והטיוטה נשמרת', () async {
      edit(service, 0, 'ראשון');
      final v1 = (await get(service, session))['draft']['version'] as int;
      edit(service, 0, 'שני');
      final v2 = (await get(service, session))['draft']['version'] as int;
      expect(v2, greaterThan(v1));
      await expectLater(
        service.acknowledge('p', draftId, v1),
        _error('error.revision_conflict'),
      );
      final draft = await service.getDraft('p', draftId);
      expect(draft['version'], v2);
      expect((draft['changes'] as List).single['proposedText'], 'שני');
    });

    test('ack מדויק מנקה, כפול מזוהה, והסשן ממשיך לגרסה גבוהה יותר', () async {
      edit(service, 0, 'לפני אישור');
      final v1 = (await get(service, session))['draft']['version'] as int;
      expect(await service.acknowledge('p', draftId, v1), {
        'draftId': draftId,
        'version': v1,
        'acknowledged': true,
        'duplicate': false,
      });
      await expectLater(
        service.getDraft('p', draftId),
        _error('error.not_found'),
      );
      expect(await service.listDrafts('p'), isEmpty);
      expect(
        (await service.acknowledge('p', draftId, v1))['duplicate'],
        isTrue,
      );

      expect(service.hasSessionForTab('tab'), isTrue);
      edit(service, 1, 'אחרי אישור');
      final next = await get(service, session);
      final v2 = next['draft']['version'] as int;
      expect(v2, greaterThan(v1));
      final draft = await service.getDraft('p', draftId);
      expect(draft['version'], v2);
      expect(
        [
          for (final change in draft['changes'] as List) change['sectionIndex'],
        ],
        [0, 1],
      );
      // אישור חוזר של גרסה שכבר אושרה הוא כפול, ואינו מוחק את הגרסה החדשה.
      expect(
        (await service.acknowledge('p', draftId, v1))['duplicate'],
        isTrue,
      );
      expect((await service.getDraft('p', draftId))['version'], v2);
    });

    test('אחרי ack מדויק, begin חדש אינו מחזיר recovery', () async {
      edit(service, 0, 'תיקון');
      final version = (await get(service, session))['draft']['version'] as int;
      await service.acknowledge('p', draftId, version);
      await service.end('p', session['sessionId'], 1);
      final again = await begin(service, tabId: 'other-tab');
      expect(again['recovery'], isNull);
      expect(again['changes'], isEmpty);
    });

    test('ack אחרי סיום הסשן עובד לפי draftId בלבד', () async {
      edit(service, 0, 'תיקון');
      final ended = await service.end('p', session['sessionId'], 1);
      expect(service.hasSessionForTab('tab'), isFalse);
      final draft = ended['draft'] as Map;
      expect(draft['persisted'], isTrue);
      final ack = await service.acknowledge(
        'p',
        draft['draftId'] as String,
        draft['version'] as int,
      );
      expect(ack['acknowledged'], isTrue);
      expect(ack['duplicate'], isFalse);
      expect(await service.listDrafts('p'), isEmpty);
    });

    test('תוסף אחר אינו מאשר ואינו קורא טיוטה שאינה שלו', () async {
      edit(service, 0, 'תיקון');
      final version = (await get(service, session))['draft']['version'] as int;
      await expectLater(
        service.acknowledge('other', draftId, version),
        _error('error.not_found'),
      );
      await expectLater(
        service.getDraft('other', draftId),
        _error('error.not_found'),
      );
      expect(await service.listDrafts('other'), isEmpty);
      expect((await service.getDraft('p', draftId))['version'], version);
      await expectLater(
        service.acknowledge('p', '', version),
        _error('error.invalid_params'),
      );
      await expectLater(
        service.acknowledge('p', draftId, -1),
        _error('error.invalid_params'),
      );
    });
  });

  group('כתיבות', () {
    test(
      'הקלדה מהירה מול מאגר איטי: כתיבה אחת בכל פעם, האחרונה נשמרת',
      () async {
        PluginCorrectionSessionService.writeInterval = Duration.zero;
        final repository = controlledConnection();
        final service = newService(repository);
        final session = await begin(service);
        repository.gate = Completer<void>();
        for (var i = 0; i < 30; i++) {
          edit(service, i % 5, 'גרסה $i');
        }
        await _idle();
        expect(repository.attempts, [1]);
        expect(
          service.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.saving,
        );
        repository.open();
        final latest = await get(service, session);
        expect(latest['revision'], 30);
        expect(latest['draft']['persisted'], isTrue);
        expect(repository.maxInFlight, 1);
        expect(repository.committed, [
          (revision: 1, status: 'ok'),
          (revision: 30, status: 'ok'),
        ]);
        final draft = await service.getDraft('p', draftId);
        expect(draft['version'], latest['draft']['version']);
        expect(
          [
            for (final change in draft['changes'] as List)
              change['proposedText'],
          ],
          [for (var i = 25; i < 30; i++) 'גרסה $i'],
        );
      },
    );

    test('הקלדה רצופה נשמרת בקצב מוגבל, לא בכל הקשה', () async {
      final repository = controlledConnection();
      final service = newService(repository);
      final session = await begin(service);
      for (var i = 0; i < 20; i++) {
        edit(service, 0, 'הקלדה $i');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final latest = await get(service, session);
      expect(latest['draft']['persisted'], isTrue);
      expect(repository.attempts.last, 20);
      // כשנייה של הקלדה ו-250ms בין כתיבות: כ-5 כתיבות, הרבה פחות מ-20.
      expect(repository.attempts.length, lessThanOrEqualTo(10));
      expect(repository.attempts, [...repository.attempts]..sort());
      expect(repository.maxInFlight, 1);
    });

    test(
      'כשל כתיבה: לא persisted, התוכן השמור נשאר, ניסיון חוזר מצליח',
      () async {
        final repository = controlledConnection();
        final service = newService(repository);
        final session = await begin(service);
        edit(service, 0, 'נשמר');
        final good = await get(service, session);
        final goodVersion = good['draft']['version'] as int;

        repository.failWrites = 2;
        edit(service, 0, 'ממתין לשמירה');
        final failed = await get(service, session);
        expect(failed['draft']['persisted'], isFalse);
        expect(failed['draft']['pending'], isFalse);
        expect(failed['draft']['error'], contains('disk full'));
        // התוכן כאן אינו התוכן העמיד, ולכן אין גרסה לאישור.
        expect(failed['draft']['version'], isNull);
        expect(
          service.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.failed,
        );
        final stored = await service.getDraft('p', draftId);
        expect(stored['version'], goodVersion);
        expect((stored['changes'] as List).single['proposedText'], 'נשמר');

        service.retryDraftWrites();
        await _idle();
        expect(
          service.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.failed,
        );
        service.retryDraftWrites();
        await _idle();
        final recovered = await get(service, session);
        expect(recovered['draft']['persisted'], isTrue);
        expect(recovered['draft']['error'], isNull);
        expect(recovered['draft']['version'], greaterThan(goodVersion));
        expect(
          ((await service.getDraft('p', draftId))['changes'] as List)
              .single['proposedText'],
          'ממתין לשמירה',
        );
      },
    );

    test('כשל זמני מתאושש לבד אחרי backoff', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      fakeAsync((async) {
        final repository = _ControlledRepository(
          PluginCorrectionDraftRepository.direct(db),
        );
        final service = PluginCorrectionSessionService()
          ..draftRepository = repository;
        service.begin(
          owner: 'p',
          tabId: 'tab',
          bookId: 'ספר',
          bookUid: 'id:42',
          libraryVersion: 'v1',
          loadSource: original,
        );
        async.elapse(Duration.zero);
        repository.failWrites = 1;
        edit(service, 0, 'תיקון');
        async.elapse(Duration.zero);
        expect(
          service.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.failed,
        );
        async.elapse(
          PluginCorrectionSessionService.retryBackoff.first -
              const Duration(milliseconds: 1),
        );
        expect(repository.attempts, [1]);
        async.elapse(const Duration(milliseconds: 2));
        expect(repository.attempts, [1, 1]);
        expect(
          service.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.saved,
        );
      });
    });
  });

  group('שני הקשרים עצמאיים על אותו קובץ', () {
    test(
      'תפוס עד שהראשון מסיים; lease שהתיישן עובר, והבעלים הישן אינו דורס',
      () async {
        final windowA = newService(connection());
        final windowB = newService(connection());
        final a = await begin(windowA, tabId: 'window-a');
        edit(windowA, 0, 'מחלון א', tabId: 'window-a');
        await get(windowA, a);

        await expectLater(
          begin(windowB, tabId: 'window-b'),
          _error('error.correction_busy'),
        );
        expect(windowB.hasSessionForTab('window-b'), isFalse);
        expect(
          await begin(windowB, tabId: 'other-book', bookUid: 'id:43'),
          containsPair('recovery', null),
        );

        await windowA.end('p', a['sessionId'], 1);
        final eventsB = <_Event>[];
        final b = await begin(windowB, tabId: 'window-b', events: eventsB);
        expect(b['recovery']['restoredSectionIndices'], [0]);

        // ב-direct אין heartbeat אוטומטי: ה-lease של B מתיישן.
        now += ttl + 1;
        final windowC = newService(connection());
        final c = await begin(windowC, tabId: 'window-c');
        expect(c['recovery']['restoredSectionIndices'], [0]);

        edit(windowB, 1, 'מחלון ב אחרי אובדן', tabId: 'window-b');
        await _idle();
        expect(windowB.hasSessionForTab('window-b'), isFalse);
        final ended = eventsB.where(
          (event) => event.$1 == 'reader.correctionSessionEnded',
        );
        expect(ended.single.$2['reason'], 'ownership_lost');
        // האירוע יוצא אחרי שהמצב שלא נשמר הוצל לטיוטה של C.
        expect(ended.single.$2['snapshot']['draft']['displaced'], isTrue);
        expect(ended.single.$2['snapshot']['draft']['persisted'], isTrue);

        final draft = await windowC.getDraft('p', draftId);
        expect(
          [
            for (final change in draft['changes'] as List)
              change['proposedText'],
          ],
          ['מחלון א'],
        );
        expect(
          [
            for (final conflict in draft['conflicts'] as List)
              (conflict['proposedText'], conflict['reason']),
          ],
          [('מחלון ב אחרי אובדן', 'displaced')],
        );
        expect(windowC.hasSessionForTab('window-c'), isTrue);
        edit(windowC, 2, 'מחלון ג', tabId: 'window-c');
        expect((await get(windowC, c))['draft']['persisted'], isTrue);
      },
    );
  });

  group('סגירה', () {
    test('כתיבה ממתינה: הלשונית מדווחת עד שהכתיבה מסתיימת', () async {
      final repository = controlledConnection();
      final service = newService(repository);
      await begin(service);
      repository.gate = Completer<void>();
      edit(service, 0, 'תיקון');
      const short = Duration(milliseconds: 50);
      expect(
        await service.unpersistedTabIds(['tab', 'unknown'], timeout: short),
        {'tab'},
      );
      expect(await service.flushAll(timeout: short), isFalse);
      repository.open();
      expect(await service.unpersistedTabIds(['tab']), isEmpty);
      expect(await service.flushAll(), isTrue);
    });

    test('סגירה אחרי כשל מדווחת מיד, ואחרי תיקון — לא', () async {
      final repository = controlledConnection();
      final service = newService(repository);
      await begin(service);
      repository.failWrites = 1000;
      edit(service, 0, 'תיקון');
      final timer = Stopwatch()..start();
      expect(await service.unpersistedTabIds(['tab']), {'tab'});
      expect(
        timer.elapsed,
        lessThan(PluginCorrectionSessionService.flushTimeout),
      );
      repository.failWrites = 0;
      service.retryDraftWrites();
      await _idle();
      expect(await service.unpersistedTabIds(['tab']), isEmpty);
    });

    test('סגירה אחרי שמירה מוצלחת אינה מדווחת', () async {
      final service = newService(connection());
      final session = await begin(service);
      edit(service, 0, 'תיקון');
      await get(service, session);
      expect(await service.unpersistedTabIds(['tab']), isEmpty);
    });

    test('סשן שהסתיים בזמן כתיבה נשמר לפני אירוע הסיום', () async {
      final repository = controlledConnection();
      final service = newService(repository);
      final events = <_Event>[];
      await begin(service, events: events);
      repository.gate = Completer<void>();
      edit(service, 0, 'תיקון');
      service.removeTab('tab');
      const short = Duration(milliseconds: 50);
      expect(await service.flushAll(timeout: short), isFalse);
      expect(
        events.where((e) => e.$1 == 'reader.correctionSessionEnded'),
        isEmpty,
      );
      repository.open();
      expect(await service.flushAll(), isTrue);
      await _idle();
      final ended = events.last;
      expect(ended.$1, 'reader.correctionSessionEnded');
      expect(ended.$2['reason'], 'tab_closed');
      expect(ended.$2['snapshot']['draft']['persisted'], isTrue);
      expect((await service.listDrafts('p')).single['active'], isFalse);
    });
  });

  test('purge בזמן כתיבה ממתינה אינו מחיה את הטיוטה', () async {
    final repository = controlledConnection();
    final service = newService(repository);
    final session = await begin(service);
    edit(service, 0, 'נשמר');
    await get(service, session);
    repository.gate = Completer<void>();
    edit(service, 1, 'ממתין');
    await service.unpersistedTabIds([
      'tab',
    ], timeout: const Duration(milliseconds: 50));
    expect(repository.inFlight, 1);

    await service.purgeOwner('p');
    expect(service.hasSessionForTab('tab'), isFalse);
    await expectLater(
      service.getDraft('p', draftId),
      _error('error.not_found'),
    );

    repository.open();
    await _idle();
    expect(repository.committed.last.status, 'lost');
    await expectLater(
      service.getDraft('p', draftId),
      _error('error.not_found'),
    );
    expect(await service.listDrafts('p'), isEmpty);
    expect(
      opened.first
          .select(
            'SELECT COUNT(*) AS c FROM ${PluginCorrectionDraftStore.table}',
          )
          .first['c'],
      0,
    );
    expect((await begin(service))['recovery'], isNull);
  });

  group('אירועי שינוי מוגבלי קצב', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      // מצערת השמירה נמדדת בשעון הקיר, ש-fakeAsync אינו מזיז.
      PluginCorrectionSessionService.writeInterval = Duration.zero;
    });
    tearDown(() => db.close());

    /// סשן בתוך fakeAsync; המאגר הישיר מתקדם עם elapse.
    (PluginCorrectionSessionService, String, List<(Duration, _Event)>) start(
      FakeAsync async, {
      _ControlledRepository? repository,
    }) {
      final service = PluginCorrectionSessionService()
        ..draftRepository =
            repository ?? PluginCorrectionDraftRepository.direct(db);
      final events = <(Duration, _Event)>[];
      String? id;
      service
          .begin(
            owner: 'p',
            tabId: 'tab',
            bookId: 'ספר',
            bookUid: 'id:42',
            libraryVersion: 'v1',
            loadSource: original,
            onEvent: (topic, payload) =>
                events.add((async.elapsed, (topic, payload))),
          )
          .then((session) => id = session['sessionId'] as String);
      async.elapse(Duration.zero);
      return (service, id!, events);
    }

    List<Map<String, dynamic>> changed(List<(Duration, _Event)> events) => [
      for (final event in events)
        if (event.$2.$1 == 'reader.correctionSessionChanged') event.$2.$2,
    ];

    test('הקלדה רצופה נשלחת בכל חלון, עם איחוד פסקאות ו-revision אחרון', () {
      fakeAsync((async) {
        final repository = _ControlledRepository(
          PluginCorrectionDraftRepository.direct(db),
        );
        final (service, id, events) = start(async, repository: repository);
        final started = async.elapsed;
        for (var i = 0; i < 10; i++) {
          edit(service, i ~/ 2, 'הקלדה $i');
          async.elapse(const Duration(milliseconds: 100));
        }
        async.elapse(const Duration(milliseconds: 500));
        expect(
          [
            for (final (at, (_, payload)) in events)
              [
                (at - started).inMilliseconds,
                payload['revision'],
                payload['sectionIndices'],
                payload['sessionId'],
              ],
          ],
          [
            [
              300,
              3,
              [0, 1],
              id,
            ],
            [
              600,
              6,
              [1, 2],
              id,
            ],
            [
              900,
              9,
              [3, 4],
              id,
            ],
            [
              1200,
              10,
              [4],
              id,
            ],
          ],
        );
        expect(repository.attempts.last, 10);
        expect(
          service.draftStatusForTab('tab'),
          PluginCorrectionDraftStatus.saved,
        );
      });
    });

    test('get מרוקן אירוע ממתין מיד, ואין אירוע כפול בסוף החלון', () {
      fakeAsync((async) {
        final (service, id, events) = start(async);
        edit(service, 0, 'א');
        async.elapse(const Duration(milliseconds: 100));
        expect(events, isEmpty);
        Map<String, dynamic>? snapshot;
        service.get('p', id).then((value) => snapshot = value);
        expect(changed(events).single['sectionIndices'], [0]);
        async.elapse(const Duration(seconds: 1));
        expect(snapshot!['draft']['persisted'], isTrue);
        expect(changed(events), hasLength(1));
      });
    });

    for (final (name, finish)
        in <(String, void Function(PluginCorrectionSessionService, String))>[
          ('end', (s, id) => s.end('p', id, 2)),
          ('removeTab', (s, _) => s.removeTab('tab')),
          ('removeOwner', (s, _) => s.removeOwner('p')),
        ]) {
      test('$name שולח שינוי ממתין לפני הסיום ולא אחריו', () {
        fakeAsync((async) {
          final (service, id, events) = start(async);
          edit(service, 0, 'א');
          edit(service, 1, 'ב');
          finish(service, id);
          async.elapse(const Duration(seconds: 2));
          expect(
            [for (final event in events) event.$2.$1],
            [
              'reader.correctionSessionChanged',
              'reader.correctionSessionEnded',
            ],
          );
          expect(changed(events).single['sectionIndices'], [0, 1]);
          expect(changed(events).single['revision'], 2);
        });
      });
    }

    test('אין אירוע כשאין שינוי ממתין', () {
      fakeAsync((async) {
        final (service, id, events) = start(async);
        async.elapse(const Duration(seconds: 2));
        service.get('p', id);
        expect(service.reset('p', id, 0, 0)['revision'], 0);
        async.elapse(const Duration(seconds: 2));
        expect(events, isEmpty);
        edit(service, 0, 'א');
        async.elapse(const Duration(seconds: 2));
        service.get('p', id);
        async.elapse(const Duration(seconds: 2));
        expect(changed(events), hasLength(1));
      });
    });

    test('reset וחזרה לנוסח המקור נכללים באירוע', () {
      fakeAsync((async) {
        final (service, id, events) = start(async);
        edit(service, 0, 'א');
        edit(service, 1, 'ב');
        async.elapse(const Duration(milliseconds: 300));
        expect(changed(events).single['sectionIndices'], [0, 1]);
        service.reset('p', id, 0, 2);
        edit(service, 1, 'מקור 1');
        async.elapse(const Duration(milliseconds: 300));
        expect(changed(events).last['sectionIndices'], [0, 1]);
        expect(changed(events).last['revision'], 4);
        expect(service.isCorrected('tab', 0, 'מקור 0'), isFalse);
        expect(service.isCorrected('tab', 1, 'מקור 1'), isFalse);
      });
    });
  });

  group('רגרסיות מסקירה', () {
    /// טיוטה שמורה ומשוחררת עם תיקונים בפסקאות [indices].
    Future<int> savedDraft(List<int> indices) async {
      final first = newService(connection());
      final session = await begin(first, tabId: 'setup');
      for (final index in indices) {
        edit(first, index, 'תיקון $index', tabId: 'setup');
      }
      final ended = await first.end(
        'p',
        session['sessionId'],
        indices.length,
      );
      expect(ended['draft']['persisted'], isTrue);
      return ended['draft']['version'] as int;
    }

    test('סשן שהסתיים עם כשל כתיבה מתמשך מנסה שוב לפי backoff', () async {
      PluginCorrectionSessionService.flushTimeout = const Duration(
        milliseconds: 100,
      );
      final repository = controlledConnection();
      final service = newService(repository);
      final events = <_Event>[];
      await begin(service, events: events);
      repository.failWrites = 1 << 30;
      edit(service, 0, 'תיקון');
      service.removeTab('tab');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repository.attempts.length, lessThanOrEqualTo(2));

      final ended = events.singleWhere(
        (event) => event.$1 == 'reader.correctionSessionEnded',
      );
      expect(ended.$2['reason'], 'tab_closed');
      expect(ended.$2['snapshot']['draft']['persisted'], isFalse);
      // המצב לא נשמר, ולכן ה-lease נשאר עד שיישמר.
      await expectLater(
        begin(newService(connection()), tabId: 'other'),
        _error('error.correction_busy'),
      );
    });

    group('לשונית שנסגרה בזמן begin', () {
      for (final (name, close)
          in <(String, void Function(PluginCorrectionSessionService))>[
            ('removeTab', (s) => s.removeTab('tab')),
            ('endAll', (s) => s.endAll('window_closed')),
          ]) {
        test('$name בזמן acquire: begin נכשל וה-lease משתחרר', () async {
          final repository = controlledConnection();
          final service = newService(repository);
          final gate = repository.acquireGate = Completer<void>();
          final pending = begin(service);
          await _idle();
          close(service);
          gate.complete();
          await expectLater(pending, _error('error.not_found'));
          expect(service.hasSessionForTab('tab'), isFalse);
          await _idle();
          final other = await begin(newService(connection()), tabId: 'other');
          expect(other['recovery'], isNull);
          // הלשונית אינה נשארת מסומנת כסגורה לפתיחה הבאה.
          expect(
            await begin(service, tabId: 'tab', bookUid: 'id:43'),
            containsPair('recovery', null),
          );
        });
      }

      test('נסגרה באמצע שחזור: begin נכשל והטיוטה אינה משתנה', () async {
        final version = await savedDraft([0, 1]);
        var closed = false;
        final service = newService(connection());
        await expectLater(
          begin(
            service,
            loadSource: (index) async {
              if (index == 1) closed = true;
              if (closed) {
                throw const PluginCorrectionException(
                  'error.not_found',
                  'הלשונית נסגרה',
                );
              }
              return 'מקור $index';
            },
            validateSource: () async {
              if (closed) {
                throw const PluginCorrectionException(
                  'error.not_found',
                  'הלשונית נסגרה',
                );
              }
            },
          ),
          _error('error.not_found'),
        );
        final draft = await service.getDraft('p', draftId);
        expect(draft['version'], version);
        expect(draft['conflicts'], isEmpty);
        expect(
          [
            for (final change in draft['changes'] as List)
              change['sectionIndex'],
          ],
          [0, 1],
        );
      });
    });

    test('ack בזמן שחזור: begin נכשל והתוכן שאושר אינו חוזר', () async {
      final version = await savedDraft([0]);
      final service = newService(connection());
      final loading = Completer<void>();
      final release = Completer<void>();
      final pending = begin(
        service,
        loadSource: (index) async {
          if (!loading.isCompleted) loading.complete();
          await release.future;
          return 'מקור $index';
        },
      );
      await loading.future;
      expect(
        await service.acknowledge('p', draftId, version),
        containsPair('acknowledged', true),
      );
      release.complete();
      await expectLater(pending, _error('error.revision_conflict'));
      expect(service.hasSessionForTab('tab'), isFalse);
      await expectLater(
        service.getDraft('p', draftId),
        _error('error.not_found'),
      );
      expect(await service.listDrafts('p'), isEmpty);
      await _idle();
      expect((await begin(service))['recovery'], isNull);
    });

    test('shutdown מסיים ב-app_exit, שומר ומשחרר את ה-lease', () async {
      final service = newService(connection());
      final events = <_Event>[];
      await begin(service, events: events);
      edit(service, 0, 'תיקון');
      await service.shutdown(timeout: const Duration(seconds: 3));
      expect(service.hasSessionForTab('tab'), isFalse);
      final ended = events.last;
      expect(ended.$1, 'reader.correctionSessionEnded');
      expect(ended.$2['reason'], 'app_exit');
      expect(ended.$2['snapshot']['draft']['persisted'], isTrue);

      // הפעלה מחדש מיידית — בלי להמתין לפקיעת ה-lease.
      final restarted = await begin(newService(connection()), tabId: 'next');
      expect(restarted['recovery']['restoredSectionIndices'], [0]);
    });

    test('קריאת מקור שנכשלה זמנית אינה הופכת תיקון להתנגשות', () async {
      final version = await savedDraft([0, 1]);
      final service = newService(connection());
      await expectLater(
        begin(
          service,
          loadSource: (index) async => index == 1
              ? throw StateError('database is locked')
              : 'מקור $index',
        ),
        _error('error.storage_failed'),
      );
      expect(service.hasSessionForTab('tab'), isFalse);
      final draft = await service.getDraft('p', draftId);
      expect(draft['version'], version);
      expect(draft['conflicts'], isEmpty);
      expect((draft['changes'] as List), hasLength(2));

      await _idle();
      final retried = await begin(service);
      expect(retried['recovery']['restoredSectionIndices'], [0, 1]);
      expect(retried['recovery']['conflicts'], isEmpty);
    });

    test('תשובת כתיבה שאבדה: הניסיון החוזר (stale) מאמץ את הגרסה', () async {
      PluginCorrectionSessionService.writeInterval = Duration.zero;
      final repository = controlledConnection();
      final service = newService(repository);
      final session = await begin(service);
      edit(service, 0, 'א');
      await get(service, session);
      repository.loseReplies = 1;
      edit(service, 0, 'ב');
      await _idle();
      expect(
        service.draftStatusForTab('tab'),
        PluginCorrectionDraftStatus.failed,
      );
      service.retryDraftWrites();
      final latest = await get(service, session);
      expect(repository.committed.last, (revision: 2, status: 'stale'));
      expect(latest['draft']['persisted'], isTrue);
      final stored = await service.getDraft('p', draftId);
      expect(latest['draft']['version'], stored['version']);
      expect(
        await service.acknowledge('p', draftId, stored['version'] as int),
        containsPair('acknowledged', true),
      );
    });

    test('טיוטה שהתרוקנה ושוחררה נמחקת; ack לגרסתה מחזיר not_found', () async {
      final service = newService(connection());
      final session = await begin(service);
      edit(service, 0, 'תיקון');
      final v1 = (await get(service, session))['draft']['version'] as int;
      edit(service, 0, 'מקור 0');
      final emptied = await service.end('p', session['sessionId'], 2);
      final v2 = emptied['draft']['version'] as int;
      for (final version in [v1, v2]) {
        await expectLater(
          service.acknowledge('p', draftId, version),
          _error('error.not_found'),
        );
      }
    });
  });

  group('worker', () {
    test('פתיחת מסד שנכשלה אינה תוקעת קריאות או dispose', () async {
      final repository = PluginCorrectionDraftRepository.isolate(
        dbPath: () async => p.join(temp.path, 'missing', 'dir', 'db.sqlite'),
      );
      await expectLater(
        repository.list('p').timeout(const Duration(seconds: 10)),
        throwsA(isA<StateError>()),
      );
      await repository.dispose().timeout(const Duration(seconds: 2));
    });
  });

  group('סקירה 2: מצב שלא נשמר אינו נעלם', () {
    test(
      'סשן שהסתיים ולא נשמר נשאר גלוי לבדיקת הסגירה עד שנשמר',
      () async {
        PluginCorrectionSessionService.flushTimeout = const Duration(
          milliseconds: 10,
        );
        final repository = controlledConnection();
        final service = newService(repository);
        await begin(service);
        repository.failWrites = 100;
        edit(service, 0, 'לא נשמר אחרי סיום');
        await _idle();
        service.endByUser('tab');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(service.hasSessionForTab('tab'), isFalse);
        expect(
          await service.flushAll(timeout: const Duration(milliseconds: 10)),
          isFalse,
        );
        expect(await service.unpersistedTabIds(['tab']), {'tab'});
        expect(await service.unsavedStates(), [
          (tabId: 'tab', ownerName: 'p', bookId: 'ספר'),
        ]);

        // ניסיון חוזר מצליח — ואז אין עוד אזהרה.
        repository.failWrites = 0;
        service.retryDraftWrites();
        await _idle();
        expect(await service.unsavedStates(), isEmpty);
        expect(
          ((await service.getDraft('p', draftId))['changes'] as List)
              .single['proposedText'],
          'לא נשמר אחרי סיום',
        );
      },
    );

    test('מחיקה באישור המשתמש אינה מוצגת כמצב שלא נשמר', () async {
      PluginCorrectionSessionService.flushTimeout = const Duration(
        milliseconds: 10,
      );
      final repository = controlledConnection();
      final service = newService(repository);
      await begin(service);
      repository.failWrites = 100;
      edit(service, 0, 'יימחק');
      service.endByUser('tab');
      await _idle();
      expect(await service.unsavedStates(), isNotEmpty);
      await service.purgeOwner('p');
      expect(await service.unsavedStates(), isEmpty);
      expect(await service.flushAll(), isTrue);
    });

    test(
      'שני הקשרים, ללא צרכן לאירוע: השינוי האחרון של בעלים שנדחק נשמר '
      'כהתנגשות, והבעלים החדש אינו נדרס',
      () async {
        // בלי flushTimeout קצר: get שחוזר לפני הכתיבה מאפשר לה לרוץ אחרי
        // הזזת השעון ולרענן את ה-lease, ו-B נכשל ב-correction_busy.
        PluginCorrectionSessionService.writeInterval = Duration.zero;
        final repositoryA = controlledConnection();
        final windowA = newService(repositoryA);
        final a = await begin(windowA);
        edit(windowA, 0, 'נשמר');
        edit(windowA, 1, 'יאופס');
        await get(windowA, a);

        repositoryA.gate = Completer<void>();
        edit(windowA, 0, 'האחרון שלא נשמר');
        windowA.reset('p', a['sessionId'], 1, 3);
        now += ttl + 1;
        final windowB = newService(connection());
        final b = await begin(windowB, tabId: 'tab-b');
        expect(b['recovery']['restoredSectionIndices'], [0, 1]);
        edit(windowB, 2, 'של B', tabId: 'tab-b');
        await get(windowB, b);

        // ההצלה נכשלת תחילה: המצב עדיין לא שמור ומדווח ככזה.
        repositoryA.failRescues = 100;
        repositoryA.open();
        await _idle();
        expect(windowA.hasSessionForTab('tab'), isFalse);
        expect(
          await windowA.flushAll(timeout: const Duration(milliseconds: 10)),
          isFalse,
        );
        expect(await windowA.unpersistedTabIds(['tab']), {'tab'});

        repositoryA.failRescues = 0;
        windowA.retryDraftWrites();
        await _idle();
        expect(repositoryA.rescues, greaterThan(1));
        expect(await windowA.flushAll(), isTrue);

        final draft = await windowB.getDraft('p', draftId);
        expect(
          {
            for (final change in draft['changes'] as List)
              change['sectionIndex']: change['proposedText'],
          },
          {0: 'נשמר', 1: 'יאופס', 2: 'של B'},
          reason: 'ה-changes של הבעלים החדש לא נדרסו',
        );
        expect(
          [
            for (final conflict in draft['conflicts'] as List)
              (
                conflict['sectionIndex'],
                conflict['proposedText'],
                conflict['reason'],
              ),
          ],
          [
            (0, 'האחרון שלא נשמר', 'displaced'),
            // איפוס שלא נשמר: הצעה לחזור לנוסח המקור.
            (1, 'מקור 1', 'displaced'),
          ],
        );

        // הבעלים החדש ממשיך לכתוב בלי למחוק את ההתנגשויות, ורואה אותן.
        edit(windowB, 3, 'עוד של B', tabId: 'tab-b');
        final latest = await get(windowB, b);
        expect(latest['draft']['conflicts'], hasLength(2));
        expect(latest['draft']['persisted'], isTrue);
      },
    );

    test('הצלה אחרי מחיקה מכוונת בהקשר אחר אינה מחיה את הטיוטה', () async {
      PluginCorrectionSessionService.writeInterval = Duration.zero;
      final repositoryA = controlledConnection();
      final windowA = newService(repositoryA);
      final a = await begin(windowA);
      edit(windowA, 0, 'נשמר');
      await get(windowA, a);
      repositoryA.gate = Completer<void>();
      edit(windowA, 0, 'ממתין');
      now += ttl + 1;
      final windowB = newService(connection());
      await begin(windowB, tabId: 'tab-b');
      await windowB.purgeOwner('p');

      repositoryA.open();
      await _idle();
      expect(repositoryA.rescues, 1);
      expect(await windowA.flushAll(), isTrue);
      expect(await windowA.unsavedStates(), isEmpty);
      expect(await windowB.listDrafts('p'), isEmpty);
    });
  });

  group('סקירה 3: אישור, כתיבה לא ודאית ומכסה', () {
    test(
      'snapshot של סשן שהוצל אינו מאפשר אישור, ו-snapshot הסיום של הבעלים '
      'החדש כולל את ההצלה',
      () async {
        PluginCorrectionSessionService.writeInterval = Duration.zero;
        final repositoryA = controlledConnection();
        final eventsA = <_Event>[];
        final windowA = newService(repositoryA);
        final a = await begin(windowA, events: eventsA);
        edit(windowA, 0, 'נשמר אצל A');
        final savedA = await get(windowA, a);
        repositoryA.gate = Completer<void>();
        edit(windowA, 0, 'האחרון של A');
        now += ttl + 1;
        final eventsB = <_Event>[];
        final windowB = newService(connection());
        final b = await begin(windowB, tabId: 'tab-b', events: eventsB);
        edit(windowB, 1, 'ייחודי ל-B', tabId: 'tab-b');
        await get(windowB, b);
        repositoryA.open();
        await _idle();
        expect(await windowA.flushAll(), isTrue);
        await _idle();

        final ended = eventsA.lastWhere(
          (e) => e.$1 == 'reader.correctionSessionEnded',
        );
        final snapshot = ended.$2['snapshot'] as Map;
        expect(ended.$2['reason'], 'ownership_lost');
        expect(snapshot['draft']['persisted'], isTrue);
        expect(snapshot['draft']['displaced'], isTrue);
        expect(
          snapshot['draft']['version'],
          isNull,
          reason: 'התוכן ב-snapshot של A חלקי ביחס לטיוטה המשותפת',
        );
        // גם גרסה ש-A ראה קודם אינה מוחקת את התוכן של B.
        await expectLater(
          windowA.acknowledge('p', draftId, savedA['draft']['version'] as int),
          _error('error.revision_conflict'),
        );

        final latestB = await get(windowB, b);
        await windowB.end('p', b['sessionId'], latestB['revision'] as int);
        final endedB =
            eventsB
                    .lastWhere((e) => e.$1 == 'reader.correctionSessionEnded')
                    .$2['snapshot']
                as Map;
        final durable = await windowB.getDraft('p', draftId);
        expect(endedB['draft']['version'], durable['version']);
        expect(endedB['draft']['conflicts'], durable['conflicts']);
        expect(
          [for (final c in durable['conflicts'] as List) c['proposedText']],
          ['האחרון של A'],
        );
        expect(
          [for (final c in durable['changes'] as List) c['proposedText']],
          ['נשמר אצל A', 'ייחודי ל-B'],
        );
        // רק snapshot שמכיל את כל התוכן העמיד מאשר אותו.
        await windowB.acknowledge(
          'p',
          draftId,
          endedB['draft']['version'] as int,
        );
        expect(await windowB.listDrafts('p'), isEmpty);
      },
    );

    test(
      'getCorrectionSession של הבעלים מחזיר את הגרסה וההתנגשויות העמידות '
      'אחרי הצלה חיצונית, בלי הקלדה נוספת',
      () async {
        PluginCorrectionSessionService.writeInterval = Duration.zero;
        final repositoryA = controlledConnection();
        final windowA = newService(repositoryA);
        final a = await begin(windowA);
        edit(windowA, 0, 'נשמר אצל A');
        await get(windowA, a);
        repositoryA.gate = Completer<void>();
        edit(windowA, 1, 'הוצל מ-A');
        now += ttl + 1;
        final windowB = newService(connection());
        final b = await begin(windowB, tabId: 'tab-b');
        final before = await get(windowB, b);
        repositoryA.open();
        await _idle();
        expect(await windowA.flushAll(), isTrue);

        final snapshot = await get(windowB, b);
        final durable = await windowB.getDraft('p', draftId);
        expect(snapshot['revision'], before['revision']);
        expect(snapshot['draft']['version'], durable['version']);
        expect(snapshot['draft']['version'], isNot(before['draft']['version']));
        expect(snapshot['draft']['conflicts'], durable['conflicts']);
        expect(
          [
            for (final c in snapshot['draft']['conflicts'] as List)
              c['proposedText'],
          ],
          ['הוצל מ-A'],
        );
      },
    );

    test('snapshot שאינו שמור אינו נושא גרסה לאישור', () async {
      PluginCorrectionSessionService.writeInterval = Duration.zero;
      final repository = controlledConnection();
      final service = newService(repository);
      final session = await begin(service);
      edit(service, 0, 'נשמר');
      final saved = await get(service, session);
      expect(saved['draft']['version'], isA<int>());
      repository.failWrites = 100;
      edit(service, 0, 'נכשל');
      final failed = await get(service, session);
      expect(failed['draft']['persisted'], isFalse);
      expect(failed['draft']['version'], isNull);
    });

    // באיפוס אין commit קודם: המצב הנוכחי זהה ל-committed המקומי (ריק).
    for (final (name, saveFirst, undo, expected) in [
      ('החזרה לנוסח הקודם', true, 'ראשון', 'ראשון'),
      ('איפוס לנוסח המקור', false, 'מקור 0', 'מקור 0'),
    ]) {
      test(
        'תשובת commit שאבדה ואחריה $name: ההצלה שומרת את הביטול',
        () async {
          PluginCorrectionSessionService.writeInterval = Duration.zero;
          final repositoryA = controlledConnection();
          final windowA = newService(repositoryA);
          final a = await begin(windowA);
          if (saveFirst) {
            edit(windowA, 0, 'ראשון');
            await get(windowA, a);
          }
          repositoryA.loseReplies = 1;
          edit(windowA, 0, 'שני');
          await _idle();
          expect(
            windowA.draftStatusForTab('tab'),
            PluginCorrectionDraftStatus.failed,
          );
          repositoryA.gate = Completer<void>();
          edit(windowA, 0, undo);
          now += ttl + 1;
          final windowB = newService(connection());
          final b = await begin(windowB, tabId: 'tab-b');
          expect((b['changes'] as List).single['proposedText'], 'שני');
          repositoryA.open();
          expect(await windowA.flushAll(), isTrue);
          await _idle();

          final stored = await windowB.getDraft('p', draftId);
          expect(
            [
              for (final c in stored['conflicts'] as List)
                (c['sectionIndex'], c['proposedText'], c['reason']),
            ],
            [(0, expected, 'displaced')],
            reason: 'הביטול שורד commit לא ודאי והעברת בעלות',
          );
          expect(
            [for (final c in stored['changes'] as List) c['proposedText']],
            ['שני'],
            reason: 'הבעלים החדש אינו נדרס',
          );
        },
      );
    }

    test('פתיחות מקבילות אינן עוקפות את maxSessions', () async {
      final service = newService(connection());
      final accepted = await Future.wait([
        for (var i = 0; i <= PluginCorrectionSessionService.maxSessions; i++)
          () async {
            try {
              await begin(service, tabId: 'quota-$i', bookUid: 'id:quota-$i');
              return true;
            } on PluginCorrectionException catch (e) {
              if (e.code != 'error.limit_exceeded') rethrow;
              return false;
            }
          }(),
      ]);
      expect(
        accepted.where((v) => v),
        hasLength(PluginCorrectionSessionService.maxSessions),
      );
    });

    test('פתיחה שבוטלה משחררת את מקומה במכסה', () async {
      final repository = controlledConnection();
      final service = newService(repository);
      for (var i = 0; i < PluginCorrectionSessionService.maxSessions - 1; i++) {
        await begin(service, tabId: 'quota-$i', bookUid: 'id:quota-$i');
      }
      repository.acquireGate = Completer<void>();
      final pending = begin(service, tabId: 'pending', bookUid: 'id:pending');
      await _idle();
      await expectLater(
        begin(service, tabId: 'extra', bookUid: 'id:extra'),
        _error('error.limit_exceeded'),
      );
      service.removeTab('pending');
      repository.acquireGate!.complete();
      repository.acquireGate = null;
      await expectLater(pending, _error('error.not_found'));
      await begin(service, tabId: 'extra', bookUid: 'id:extra');
      expect(service.hasSessionForTab('extra'), isTrue);
    });
  });
}
