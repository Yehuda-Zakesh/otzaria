import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';
import 'package:path/path.dart' as p;

String _changes(List<String> proposed) => jsonEncode([
  for (var i = 0; i < proposed.length; i++)
    {
      'sectionIndex': i,
      'originalSourceText': 'מקור $i',
      'originalText': 'מקור $i',
      'proposedText': proposed[i],
    },
]);

void main() {
  late Directory temp;
  late String dbPath;
  final opened = <Database>[];
  var now = 1000000;

  Database open() {
    final db = openWritableDatabase(dbPath, 'test');
    opened.add(db);
    return db;
  }

  PluginCorrectionDraftRepository context() =>
      PluginCorrectionDraftRepository.direct(open(), nowMs: () => now);

  Future<String> acquire(PluginCorrectionDraftRepository repo) async =>
      (await repo.acquire(
        pluginId: 'p',
        draftId: correctionDraftId('p', 'id:1'),
        bookUid: 'id:1',
        bookId: 'בראשית',
        bookSource: 'official',
        libraryVersion: 'v1',
      )).token;

  Future<({String status, int? version, String? conflicts})> write(
    PluginCorrectionDraftRepository repo,
    String token,
    int revision,
    List<String> proposed, {
    String? conflicts,
  }) => repo.write(
    pluginId: 'p',
    draftId: correctionDraftId('p', 'id:1'),
    token: token,
    revision: revision,
    libraryVersion: 'v1',
    changesJson: _changes(proposed),
    conflictsJson: conflicts,
  );

  final draftId = correctionDraftId('p', 'id:1');

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('correction-drafts-');
    dbPath = p.join(temp.path, 'plugins_host.db');
    now = 1000000;
  });

  tearDown(() async {
    for (final db in opened) {
      db.close();
    }
    opened.clear();
    await temp.delete(recursive: true);
  });

  test('draftId יציב ואינו מתנגש בשרשור מחרוזות', () {
    expect(correctionDraftId('p', 'id:1'), correctionDraftId('p', 'id:1'));
    expect(
      correctionDraftId('a', 'bc'),
      isNot(correctionDraftId('ab', 'c')),
    );
    expect(correctionDraftId('p', 'id:1'), isNot(contains('=')));
  });

  test('טיוטה שורדת סגירת חיבור וחוזרת לבעלים חדש לשחזור', () async {
    final first = context();
    final token = await acquire(first);
    final saved = await write(first, token, 1, ['תיקון']);
    expect(saved.status, 'ok');
    await first.release(pluginId: 'p', draftId: draftId, token: token);
    opened.single.close();
    opened.clear();

    final reopened = context();
    final lease = await reopened.acquire(
      pluginId: 'p',
      draftId: draftId,
      bookUid: 'id:1',
      bookId: 'בראשית',
      bookSource: 'official',
      libraryVersion: 'v2',
    );
    expect(lease.version, saved.version);
    expect((jsonDecode(lease.changes) as List).single['proposedText'], 'תיקון');
  });

  test('שני הקשרים עצמאיים: הבעלים השני נדחה כל עוד הראשון חי', () async {
    final windowA = context();
    final windowB = context();
    final tokenA = await acquire(windowA);
    await expectLater(
      acquire(windowB),
      throwsA(isA<PluginCorrectionDraftBusy>()),
    );
    now += PluginCorrectionDraftRepository.leaseTtl.inMilliseconds - 1;
    await windowA.heartbeat();
    now += PluginCorrectionDraftRepository.leaseTtl.inMilliseconds - 1;
    await expectLater(
      acquire(windowB),
      throwsA(isA<PluginCorrectionDraftBusy>()),
    );
    await windowA.release(pluginId: 'p', draftId: draftId, token: tokenA);
    expect(await acquire(windowB), isNotEmpty);
  });

  test('בעלים שהתיישן אינו כותב ואינו משחרר את הבעלים החדש', () async {
    final crashed = context();
    final fresh = context();
    final oldToken = await acquire(crashed);
    expect((await write(crashed, oldToken, 1, ['ישן'])).status, 'ok');
    now += PluginCorrectionDraftRepository.leaseTtl.inMilliseconds + 1;
    final newToken = await acquire(fresh);
    expect((await write(crashed, oldToken, 2, ['דורס'])).status, 'lost');
    await crashed.release(pluginId: 'p', draftId: draftId, token: oldToken);
    expect(
      await acquire(context()).then((_) => 'acquired', onError: (_) => 'busy'),
      'busy',
    );
    final saved = await write(fresh, newToken, 1, ['חדש']);
    expect(saved.status, 'ok');
    final draft = await fresh.get('p', draftId);
    expect((draft!['changes'] as List).single['proposedText'], 'חדש');
  });

  test('כתיבה ישנה אינה דורסת revision חדש יותר', () async {
    final repo = context();
    final token = await acquire(repo);
    expect((await write(repo, token, 3, ['שלישי'])).status, 'ok');
    expect((await write(repo, token, 2, ['שני'])).status, 'stale');
    final draft = await repo.get('p', draftId);
    expect((draft!['changes'] as List).single['proposedText'], 'שלישי');
  });

  test('כתיבה stale מחזירה את הגרסה וה-conflicts השמורים', () async {
    final repo = context();
    final token = await acquire(repo);
    final conflicts = jsonEncode([
      {'sectionIndex': 7, 'reason': 'source_changed'},
    ]);
    final saved = await write(repo, token, 2, ['ב'], conflicts: conflicts);
    final stale = await write(repo, token, 2, ['ב']);
    expect(stale.status, 'stale');
    expect(stale.version, saved.version);
    expect(stale.conflicts, conflicts);
  });

  test('כתיבה עם expectedVersion נדחית אחרי ack או שינוי גרסה', () async {
    final repo = context();
    final token = await acquire(repo);
    final v1 = (await write(repo, token, 1, ['א'])).version!;
    final v2 = (await write(repo, token, 2, ['ב'])).version!;
    Future<String> guarded(int expectedVersion) async => (await repo.write(
      pluginId: 'p',
      draftId: draftId,
      token: token,
      revision: 3,
      libraryVersion: 'v1',
      changesJson: _changes(['ג']),
      expectedVersion: expectedVersion,
    )).status;
    expect(await guarded(v1), 'conflict');
    await repo.acknowledge(pluginId: 'p', draftId: draftId, version: v2);
    expect(await guarded(v2), 'conflict');
    expect(await repo.get('p', draftId), isNull);
  });

  test('הקשר חדש (worker שעלה מחדש) לומד מהכתיבה לחדש את ה-lease', () async {
    final ttl = PluginCorrectionDraftRepository.leaseTtl.inMilliseconds;
    final token = await acquire(context());
    // אותו token דרך executor חדש, שאינו יודע שה-lease בידיו.
    final restarted = context();
    expect((await write(restarted, token, 1, ['א'])).status, 'ok');
    now += ttl - 1;
    await restarted.heartbeat();
    now += ttl - 1;
    await expectLater(
      acquire(context()),
      throwsA(isA<PluginCorrectionDraftBusy>()),
    );
  });

  test('כתיבה רגילה שומרת conflicts ומחזירה אותם', () async {
    final repo = context();
    final token = await acquire(repo);
    final conflicts = jsonEncode([
      {'sectionIndex': 7, 'reason': 'source_changed'},
    ]);
    await write(repo, token, 1, ['א'], conflicts: conflicts);
    final next = await write(repo, token, 2, ['ב']);
    expect(next.conflicts, conflicts);
    expect(
      ((await repo.get('p', draftId))!['conflicts'] as List)
          .single['sectionIndex'],
      7,
    );
  });

  test('ack מוחק רק את הגרסה המדויקת; ישן נדחה, כפול מזוהה', () async {
    final repo = context();
    final token = await acquire(repo);
    final v1 = (await write(repo, token, 1, ['א'])).version!;
    final v2 = (await write(repo, token, 2, ['ב'])).version!;
    expect(v2, greaterThan(v1));
    final stale = await repo.acknowledge(
      pluginId: 'p',
      draftId: draftId,
      version: v1,
    );
    expect(stale, {'status': 'conflict', 'currentVersion': v2});
    expect(await repo.get('p', draftId), isNotNull);
    expect(
      (await repo.acknowledge(
        pluginId: 'p',
        draftId: draftId,
        version: v2,
      ))['status'],
      'acknowledged',
    );
    expect(await repo.get('p', draftId), isNull);
    expect(
      (await repo.acknowledge(
        pluginId: 'p',
        draftId: draftId,
        version: v2,
      ))['status'],
      'duplicate',
    );
    // אותו revision שאושר אינו נכתב שוב; שינוי חדש הוא גרסה חדשה.
    expect((await write(repo, token, 2, ['ב'])).status, 'stale');
    final v3 = (await write(repo, token, 3, ['ג'])).version!;
    // אישור חוזר של v2 מדווח כפול, ואינו מוחק את v3.
    expect(
      (await repo.acknowledge(
        pluginId: 'p',
        draftId: draftId,
        version: v2,
      ))['status'],
      'duplicate',
    );
    expect((await repo.get('p', draftId))!['version'], v3);
    expect(v3, greaterThan(v2));
  });

  test('גרסה אינה חוזרת אחרי purge ויצירה מחדש', () async {
    final repo = context();
    final token = await acquire(repo);
    final before = (await write(repo, token, 1, ['א'])).version!;
    await repo.purge('p');
    expect((await write(repo, token, 2, ['תחייה'])).status, 'lost');
    expect(await repo.get('p', draftId), isNull);
    final again = await acquire(repo);
    final after = (await write(repo, again, 1, ['א'])).version!;
    expect(after, greaterThan(before));
    expect(
      (await repo.acknowledge(
        pluginId: 'p',
        draftId: draftId,
        version: before,
      ))['status'],
      'conflict',
    );
  });

  test('שחרור משאיר טיוטה עם תוכן ומוחק lease ריק', () async {
    final repo = context();
    final empty = await acquire(repo);
    await repo.release(pluginId: 'p', draftId: draftId, token: empty);
    expect(
      opened.single
          .select('SELECT COUNT(*) AS c FROM plugin_correction_draft')
          .first['c'],
      0,
    );
    final token = await acquire(repo);
    await write(repo, token, 1, ['א']);
    await repo.release(pluginId: 'p', draftId: draftId, token: token);
    final listed = await repo.list('p');
    expect(listed.single['changeCount'], 1);
    expect(listed.single['active'], isFalse);
    expect(await repo.list('other'), isEmpty);
  });

  test(
    'worker אמיתי: שני חלונות מתחרים, heartbeat מחזיק, הסגירה משחררת',
    () async {
      final a = PluginCorrectionDraftRepository.isolate(
        dbPath: () async => dbPath,
      );
      final b = PluginCorrectionDraftRepository.isolate(
        dbPath: () async => dbPath,
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final token = await acquire(a);
      await expectLater(acquire(b), throwsA(isA<PluginCorrectionDraftBusy>()));
      expect((await write(a, token, 1, ['מה-worker'])).status, 'ok');
      await a.release(pluginId: 'p', draftId: draftId, token: token);
      final lease = await b.acquire(
        pluginId: 'p',
        draftId: draftId,
        bookUid: 'id:1',
        bookId: 'בראשית',
        bookSource: 'official',
        libraryVersion: 'v1',
      );
      expect(
        (jsonDecode(lease.changes) as List).single['proposedText'],
        'מה-worker',
      );
    },
  );

  group('rescue', () {
    Future<({String status, int? version})> rescue(
      PluginCorrectionDraftRepository repo,
      List<String> proposed, {
      required int sinceEpoch,
    }) => repo.rescue(
      pluginId: 'p',
      draftId: draftId,
      bookUid: 'id:1',
      bookId: 'בראשית',
      bookSource: 'official',
      libraryVersion: 'v1',
      entriesJson: jsonEncode([
        for (final change in jsonDecode(_changes(proposed)) as List)
          {...change as Map, 'reason': 'displaced'},
      ]),
      sinceEpoch: sinceEpoch,
    );

    test('מוסיף התנגשויות בלבד, בלי לגעת ב-changes או ב-holder', () async {
      final owner = context();
      final lease = await owner.acquire(
        pluginId: 'p',
        draftId: draftId,
        bookUid: 'id:1',
        bookId: 'בראשית',
        bookSource: 'official',
        libraryVersion: 'v1',
      );
      final saved = await write(owner, lease.token, 1, ['של הבעלים']);
      final rescued = await rescue(context(), [
        'של הבעלים',
        'שנדחק',
      ], sinceEpoch: lease.epoch);
      expect(rescued.status, 'ok');
      expect(rescued.version, greaterThan(saved.version!));
      final draft = (await owner.get('p', draftId))!;
      expect((draft['changes'] as List).single['proposedText'], 'של הבעלים');
      expect(
        [
          for (final conflict in draft['conflicts'] as List)
            (conflict['sectionIndex'], conflict['proposedText']),
        ],
        [(1, 'שנדחק')],
        reason: 'זהה ל-changes אינו משוכפל',
      );
      // הבעלים ממשיך לכתוב ושומר את ההתנגשות.
      final next = await write(owner, lease.token, 2, ['של הבעלים 2']);
      expect(jsonDecode(next.conflicts!) as List, hasLength(1));
      // הצלה חוזרת של מצב שכבר קיים אינה משכפלת ואינה מעלה גרסה.
      final again = await rescue(context(), [
        'של הבעלים 2',
        'שנדחק',
      ], sinceEpoch: lease.epoch);
      expect(again.version, next.version);
      // הצעה ישנה שהבעלים כבר שינה נשמרת כהתנגשות, ואינה דורסת את changes.
      final stale = await rescue(context(), [
        'של הבעלים',
      ], sinceEpoch: lease.epoch);
      expect(stale.version, greaterThan(next.version!));
      final draft2 = (await owner.get('p', draftId))!;
      expect((draft2['changes'] as List).single['proposedText'], 'של הבעלים 2');
      expect(draft2['conflicts'], hasLength(2));
    });

    test('יוצר טיוטה כשהבעלים החדש שחרר טיוטה שהתרוקנה', () async {
      final repo = context();
      final token = await acquire(repo);
      final epoch = (await repo.acquire(
        pluginId: 'p',
        draftId: correctionDraftId('p', 'id:2'),
        bookUid: 'id:2',
        bookId: 'שמות',
        bookSource: 'official',
        libraryVersion: 'v1',
      )).epoch;
      await repo.release(pluginId: 'p', draftId: draftId, token: token);
      expect(await repo.get('p', draftId), isNull);
      expect((await rescue(repo, ['שנדחק'], sinceEpoch: epoch)).status, 'ok');
      final draft = (await repo.get('p', draftId))!;
      expect(draft['changes'], isEmpty);
      expect((draft['conflicts'] as List).single['reason'], 'displaced');
      expect(draft['active'], isFalse);
    });

    test('אינו מחיה טיוטה שנמחקה באישור המשתמש אחרי פתיחת הסשן', () async {
      final repo = context();
      final lease = await repo.acquire(
        pluginId: 'p',
        draftId: draftId,
        bookUid: 'id:1',
        bookId: 'בראשית',
        bookSource: 'official',
        libraryVersion: 'v1',
      );
      await repo.purge('p');
      expect(
        (await rescue(repo, ['שנדחק'], sinceEpoch: lease.epoch)).status,
        'purged',
      );
      expect(await repo.list('p'), isEmpty);
      // סשן שנפתח אחרי המחיקה רשאי להציל.
      final later = await repo.acquire(
        pluginId: 'p',
        draftId: draftId,
        bookUid: 'id:1',
        bookId: 'בראשית',
        bookSource: 'official',
        libraryVersion: 'v1',
      );
      expect(
        (await rescue(repo, ['אחרי'], sinceEpoch: later.epoch)).status,
        'ok',
      );
    });
  });
}
