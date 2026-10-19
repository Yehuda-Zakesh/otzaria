import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:path/path.dart' as p;

typedef _Json = Map<String, dynamic>;

const _owner = 'p';
const _bookUid = 'id:42';

String _conflictKey(Map c) =>
    jsonEncode([c['sectionIndex'], c['originalSourceText'], c['proposedText']]);

String _changeKey(Map c) => '${c['sectionIndex']}|${c['proposedText']}';

/// העתק של המתכון ב-docs/plugin-sdk/COOKBOOK.md ("תיקונים מקומיים").
/// כל שינוי באלגוריתם שם חייב להשתקף כאן, ולהפך.
class _CookbookStore {
  /// storage.get/set של התוסף; ערכים נשמרים כ-JSON כמו בגשר.
  final storage = <String, String>{};

  static String recordKey(String bookUid) => 'correction.$bookUid';

  _Json? read(String key) {
    final value = storage[key];
    return value == null ? null : jsonDecode(value) as _Json;
  }

  _Json loadRecord(String bookUid, [String? bookId]) =>
      read(recordKey(bookUid)) ??
      {
        'bookUid': bookUid,
        'bookId': bookId,
        'nextSeq': 0,
        'sessions': <String, dynamic>{},
        'conflicts': <String, dynamic>{},
      };

  void store(Map source, String entryKey, List changes, List conflicts) {
    final bookUid = source['bookUid'] as String;
    final record = loadRecord(bookUid, source['bookId'] as String?);
    final sessions = record['sessions'] as _Json;
    var seq = (sessions[entryKey] as Map?)?['seq'] as int?;
    if (seq == null) {
      seq = record['nextSeq'] as int;
      record['nextSeq'] = seq + 1;
    }
    final previous = sessions[entryKey] as Map?;
    sessions[entryKey] = {
      'seq': seq,
      'changes': changes,
      'covered': {
        ...?(previous?['covered'] as List?),
        for (final change in changes) (change as Map)['sectionIndex'],
      }.toList(),
    };
    final stored = record['conflicts'] as _Json;
    for (final conflict in conflicts) {
      stored[_conflictKey(conflict as Map)] = conflict;
    }
    storage[recordKey(bookUid)] = jsonEncode(record);
  }

  Future<void> acknowledge(
    PluginCorrectionSessionService service,
    String draftId,
    int version,
  ) async {
    try {
      await service.acknowledge(_owner, draftId, version);
    } on PluginCorrectionException catch (error) {
      if (error.code != 'error.revision_conflict' &&
          error.code != 'error.not_found') {
        rethrow;
      }
    }
  }

  Future<_Json> keep(
    PluginCorrectionSessionService service,
    _Json snapshot,
  ) async {
    final draft = snapshot['draft'] as Map;
    store(
      snapshot,
      snapshot['sessionId'] as String,
      snapshot['changes'] as List,
      draft['conflicts'] as List,
    );
    final version = draft['version'] as int?;
    if (draft['persisted'] == true && version != null) {
      await acknowledge(service, draft['draftId'] as String, version);
    }
    return snapshot;
  }

  Future<void> recoverOrphans(PluginCorrectionSessionService service) async {
    for (final meta in await service.listDrafts(_owner)) {
      if (meta['active'] == true) continue;
      final draft = await service.getDraft(_owner, meta['draftId'] as String);
      store(
        draft,
        'draft:${draft['draftId']}:${draft['version']}',
        draft['changes'] as List,
        draft['conflicts'] as List,
      );
      await acknowledge(
        service,
        draft['draftId'] as String,
        draft['version'] as int,
      );
    }
  }

  List<Map> pending(String bookUid) {
    final record = read(recordKey(bookUid));
    if (record == null) return [];
    final entries = (record['sessions'] as _Json).values.cast<Map>().toList()
      ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    // בכל פסקה קובע הסשן המאוחר שהכיר אותה; היעדרה אצלו הוא ביטול.
    final bySection = <int, Map?>{};
    for (final entry in entries) {
      final changes = {
        for (final change in (entry['changes'] as List).cast<Map>())
          change['sectionIndex'] as int: change,
      };
      for (final index in (entry['covered'] as List).cast<int>()) {
        bySection[index] = changes[index];
      }
    }
    return [
      for (final index in bySection.keys.toList()..sort()) ?bySection[index],
    ];
  }

  Map<String, dynamic> conflicts(String bookUid) =>
      (read(recordKey(bookUid))?['conflicts'] as _Json?) ?? {};

  void dismissConflict(String bookUid, String key) {
    final record = loadRecord(bookUid);
    (record['conflicts'] as _Json).remove(key);
    storage[recordKey(bookUid)] = jsonEncode(record);
  }

  /// המתכון הישן: snapshot שלם במפתח אחד לספר, שמוחלף בכל שמירה.
  Future<void> naiveKeep(
    PluginCorrectionSessionService service,
    _Json snapshot,
  ) async {
    storage[recordKey(snapshot['bookUid'] as String)] = jsonEncode(snapshot);
    final draft = snapshot['draft'] as Map;
    final version = draft['version'] as int?;
    if (draft['persisted'] == true && version != null) {
      await acknowledge(service, draft['draftId'] as String, version);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late String dbPath;
  final opened = <Database>[];
  final services = <PluginCorrectionSessionService>[];

  PluginCorrectionSessionService newService() {
    final db = openWritableDatabase(dbPath, 't');
    opened.add(db);
    final service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(
        db,
        nowMs: () => 1000000,
      );
    services.add(service);
    return service;
  }

  Future<String> original(int index) async => 'מקור $index';
  Future<String> changedSource(int index) async =>
      index == 1 ? 'מקור שהשתנה' : 'מקור $index';

  Future<_Json> begin(
    PluginCorrectionSessionService service, {
    String tabId = 'tab',
    Future<String> Function(int)? loadSource,
  }) => service.begin(
    owner: _owner,
    tabId: tabId,
    bookId: 'ספר',
    bookUid: _bookUid,
    libraryVersion: 'v1',
    loadSource: loadSource ?? original,
  );

  Future<_Json> get(PluginCorrectionSessionService service, _Json session) =>
      service.get(_owner, session['sessionId'] as String);

  Future<_Json> end(PluginCorrectionSessionService service, _Json session) =>
      get(service, session).then(
        (latest) => service.end(
          _owner,
          latest['sessionId'] as String,
          latest['revision'] as int,
        ),
      );

  void edit(
    PluginCorrectionSessionService service,
    String tabId,
    int index,
    String proposed,
  ) => service.editParagraph(tabId, index, 'מקור $index', proposed);

  /// מה שידוע לשני הצדדים יחד: חנות התוסף וטיוטות אוצריא שלא אושרו.
  Future<({Set<String> changes, Set<String> conflicts})> known(
    PluginCorrectionSessionService service,
    _CookbookStore cookbook,
  ) async {
    final changes = <String>{};
    final conflicts = <String>{};
    void addConflicts(Iterable<Map> items) {
      for (final conflict in items) {
        conflicts.add(_conflictKey(conflict));
        changes.add(_changeKey(conflict));
      }
    }

    changes.addAll(cookbook.pending(_bookUid).map(_changeKey));
    addConflicts(cookbook.conflicts(_bookUid).values.cast<Map>());
    for (final meta in await service.listDrafts(_owner)) {
      final draft = await service.getDraft(_owner, meta['draftId'] as String);
      changes.addAll((draft['changes'] as List).cast<Map>().map(_changeKey));
      addConflicts((draft['conflicts'] as List).cast<Map>());
    }
    return (changes: changes, conflicts: conflicts);
  }

  Future<void> expectNoLoss(
    PluginCorrectionSessionService service,
    _CookbookStore cookbook, {
    required Set<String> changes,
    Set<String> conflicts = const {},
  }) async {
    final both = await known(service, cookbook);
    expect(both.changes, containsAll(changes));
    expect(both.conflicts, containsAll(conflicts));
  }

  const correction0 = '0|תיקון 0';
  const correction1 = '1|תיקון 1';
  final conflict1 = jsonEncode([1, 'מקור 1', 'תיקון 1']);

  /// סשן 1: פסקה 0 נשמרת ומאושרת, פסקה 1 נערכת אחר כך, ואירוע הסיום
  /// אינו מגיע לתוסף. כך נשארת טיוטה שלא אושרה לשחזור.
  Future<void> firstSession(
    _CookbookStore cookbook,
    Future<void> Function(PluginCorrectionSessionService, _Json) keep,
  ) async {
    final service = newService();
    final session = await begin(service);
    expect(session['recovery'], isNull);
    await keep(service, session);
    edit(service, 'tab', 0, 'תיקון 0');
    await keep(service, await get(service, session));
    expect(await service.listDrafts(_owner), isEmpty);
    edit(service, 'tab', 1, 'תיקון 1');
    final ended = await end(service, session);
    expect(ended['draft']['persisted'], isTrue);
    // בחנות של המתכון הישן אין רשומת ספר מובנית לבדיקה.
    if (keep == cookbook.naiveKeep) return;
    await expectNoLoss(
      service,
      cookbook,
      changes: {correction0, correction1},
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('correction-cookbook-');
    dbPath = p.join(temp.path, 'plugins_host.db');
  });

  tearDown(() async {
    for (final service in services) {
      service.endAll('test');
      await service.flushAll(timeout: const Duration(seconds: 1));
    }
    // שחרור ה-lease רץ אחרי flushAll; סגירת המסד לפניו מדפיסה שגיאה.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    services.clear();
    for (final db in opened) {
      db.close();
    }
    opened.clear();
    await temp.delete(recursive: true);
  });

  test(
    'התנגשות שאושרה ותיקון מסשן קודם אינם נדרסים בידי snapshot מאוחר',
    () async {
      final cookbook = _CookbookStore();
      await firstSession(cookbook, cookbook.keep);

      // סשן 2: מקור פסקה 1 השתנה — שחזור עם התנגשות, שמירה ואישור.
      final service = newService();
      final second = await begin(
        service,
        tabId: 'tab2',
        loadSource: changedSource,
      );
      expect(second['recovery']['restoredSectionIndices'], [0]);
      expect(
        [
          for (final c in second['recovery']['conflicts'] as List)
            _conflictKey(c as Map),
        ],
        [conflict1],
      );
      await cookbook.keep(service, second);
      expect(await service.listDrafts(_owner), isEmpty);
      await expectNoLoss(
        service,
        cookbook,
        changes: {correction0, correction1},
        conflicts: {conflict1},
      );

      // אחרי האישור אוצריא מנקה את ההתנגשויות; snapshot הסיום אינו מוחק אותן.
      final ended = await end(service, second);
      expect(ended['draft']['conflicts'], isEmpty);
      await cookbook.keep(service, ended);
      expect(cookbook.conflicts(_bookUid).keys, [conflict1]);
      await expectNoLoss(
        service,
        cookbook,
        changes: {correction0, correction1},
        conflicts: {conflict1},
      );

      // סשן 3 חדש וריק אינו מוחק את התיקונים שנשמרו.
      final third = await begin(
        service,
        tabId: 'tab3',
        loadSource: changedSource,
      );
      expect(third['recovery'], isNull);
      expect(third['changes'], isEmpty);
      await cookbook.keep(service, third);
      await cookbook.keep(service, await end(service, third));
      expect(cookbook.pending(_bookUid).map(_changeKey), [correction0]);
      expect(cookbook.conflicts(_bookUid).keys, [conflict1]);
      await expectNoLoss(
        service,
        cookbook,
        changes: {correction0, correction1},
        conflicts: {conflict1},
      );
    },
  );

  test('המתכון הישן (החלפה לפי מפתח) מאבד נתונים — תיעוד הבאג', () async {
    final cookbook = _CookbookStore();
    await firstSession(cookbook, cookbook.naiveKeep);

    Set<String> naiveConflicts() => {
      for (final c
          in cookbook.read(
                _CookbookStore.recordKey(_bookUid),
              )!['draft']['conflicts']
              as List)
        _conflictKey(c as Map),
    };
    Set<String> naiveChanges() => {
      for (final c
          in cookbook.read(_CookbookStore.recordKey(_bookUid))!['changes']
              as List)
        _changeKey(c as Map),
    };

    final service = newService();
    final second = await begin(
      service,
      tabId: 'tab2',
      loadSource: changedSource,
    );
    await cookbook.naiveKeep(service, second);
    expect(naiveConflicts(), {conflict1});

    await cookbook.naiveKeep(service, await end(service, second));
    expect(await service.listDrafts(_owner), isEmpty);
    expect(naiveConflicts(), isEmpty, reason: 'ההתנגשות אבדה בשני הצדדים');

    final third = await begin(
      service,
      tabId: 'tab3',
      loadSource: changedSource,
    );
    await cookbook.naiveKeep(service, third);
    expect(await service.listDrafts(_owner), isEmpty);
    expect(naiveChanges(), isEmpty, reason: 'תיקון פסקה 0 אבד בשני הצדדים');
  });

  test('reset בתוך סשן נשמר, ואינו נוגע ברשימות של סשנים אחרים', () async {
    final cookbook = _CookbookStore();
    final service = newService();
    final first = await begin(service);
    edit(service, 'tab', 2, 'תיקון 2');
    await cookbook.keep(service, await end(service, first));

    final second = await begin(service, tabId: 'tab2');
    expect(second['recovery'], isNull);
    edit(service, 'tab2', 0, 'תיקון 0');
    edit(service, 'tab2', 1, 'תיקון 1');
    final edited = await cookbook.keep(service, await get(service, second));
    service.reset(
      _owner,
      second['sessionId'] as String,
      1,
      edited['revision'] as int,
    );
    await cookbook.keep(service, await get(service, second));
    expect(cookbook.pending(_bookUid).map(_changeKey), [
      correction0,
      '2|תיקון 2',
    ]);
  });

  test('recoverOrphans ממזג טיוטה יתומה בלי למחוק רשומות קודמות', () async {
    final cookbook = _CookbookStore();
    await firstSession(cookbook, cookbook.keep);
    expect(cookbook.pending(_bookUid).map(_changeKey), [correction0]);

    final service = newService();
    expect((await service.listDrafts(_owner)).single['active'], isFalse);
    await cookbook.recoverOrphans(service);
    expect(await service.listDrafts(_owner), isEmpty);
    expect(
      (cookbook.read(_CookbookStore.recordKey(_bookUid))!['sessions'] as Map)
          .length,
      2,
    );
    expect(cookbook.pending(_bookUid).map(_changeKey), [
      correction0,
      correction1,
    ]);
    await expectNoLoss(
      service,
      cookbook,
      changes: {correction0, correction1},
    );
  });

  test('dismissConflict מוחק רק את ההתנגשות שנבחרה', () async {
    final cookbook = _CookbookStore();
    await firstSession(cookbook, cookbook.keep);
    final service = newService();
    final second = await begin(
      service,
      tabId: 'tab2',
      loadSource: changedSource,
    );
    await cookbook.keep(service, second);
    await cookbook.keep(service, await end(service, second));
    expect(cookbook.conflicts(_bookUid).keys, [conflict1]);

    cookbook.dismissConflict(_bookUid, conflict1);
    expect(cookbook.conflicts(_bookUid), isEmpty);
    expect(cookbook.pending(_bookUid).map(_changeKey), [correction0]);
  });

  test('reset של תיקון ששוחזר אינו מחזיר אותו מרשומת סשן קודם', () async {
    final cookbook = _CookbookStore();
    await firstSession(cookbook, cookbook.keep);
    expect(cookbook.pending(_bookUid).map(_changeKey), [correction0]);

    final service = newService();
    final second = await begin(service, tabId: 'tab2');
    expect(second['recovery']['restoredSectionIndices'], [0, 1]);
    await cookbook.keep(service, second);
    service.reset(
      _owner,
      second['sessionId'] as String,
      0,
      second['revision'] as int,
    );
    await cookbook.keep(service, await get(service, second));
    expect(
      cookbook.pending(_bookUid).map(_changeKey),
      [correction1],
      reason: 'reset הוא ביטול מפורש, לא סשן חדש וריק',
    );

    // סשן חדש וריק אחריו אינו מבטל ואינו מחזיר דבר.
    await cookbook.keep(service, await end(service, second));
    final third = await begin(service, tabId: 'tab3');
    expect(third['recovery'], isNull);
    await cookbook.keep(service, await end(service, third));
    expect(cookbook.pending(_bookUid).map(_changeKey), [correction1]);
  });

  test('מפתח ההתנגשות חד-משמעי גם כשהטקסט מכיל מפרידים', () {
    final cookbook = _CookbookStore();
    cookbook.store(
      {'bookUid': _bookUid, 'bookId': 'ספר'},
      'one',
      [],
      [
        {
          'sectionIndex': 0,
          'originalSourceText': 'a|b',
          'originalText': 'a|b',
          'proposedText': 'c',
        },
        {
          'sectionIndex': 0,
          'originalSourceText': 'a',
          'originalText': 'a',
          'proposedText': 'b|c',
        },
      ],
    );
    expect(cookbook.conflicts(_bookUid), hasLength(2));
    cookbook.dismissConflict(
      _bookUid,
      _conflictKey({
        'sectionIndex': 0,
        'originalSourceText': 'a',
        'proposedText': 'b|c',
      }),
    );
    expect(
      [for (final c in cookbook.conflicts(_bookUid).values) c['proposedText']],
      ['c'],
    );
  });
}
