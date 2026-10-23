import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/data/repository/user_state_list_repository.dart';

const String _namespace = 'otzaria.test.userstate';

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() {
    WindowBus.namespace = _namespace;
    tmp = Directory.systemTemp.createTempSync('otzaria_user_state_');
    dbPath = '${tmp.path}${Platform.pathSeparator}user_state.db';
  });

  tearDown(() {
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    WindowBus.namespace = 'otzaria.window';
    tmp.deleteSync(recursive: true);
  });

  test('WAL עם synchronous=NORMAL, busy_timeout נשאר 1000', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final conn = await db.database;
    expect(conn.select('PRAGMA journal_mode').first.values.first, 'wal');
    expect(conn.select('PRAGMA synchronous').first.values.first, 1);
    expect(conn.select('PRAGMA busy_timeout').first.values.first, 1000);
    db.close();
  });

  test('קריאה של מפתח שאינו קיים מחזירה רשימה ריקה', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final store = UserStateListStore(database: db);
    expect(await store.read('history', 'history'), isEmpty);
    db.close();
  });

  test('כתיבה, קריאה, מוטציה וניקוי', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final store = UserStateListStore(database: db);

    await store.write('bookmarks', 'key-bookmarks', [
      {'title': 'א'},
    ]);
    expect(await store.read('bookmarks', 'key-bookmarks'), hasLength(1));

    final result = await store.mutate(
      'bookmarks',
      'key-bookmarks',
      (current) => [
        ...current,
        {'title': 'ב'},
      ],
    );
    expect(result, hasLength(2));
    expect(await store.read('bookmarks', 'key-bookmarks'), hasLength(2));

    await store.clear('bookmarks', 'key-bookmarks');
    expect(await store.read('bookmarks', 'key-bookmarks'), isEmpty);
    db.close();
  });

  test('שני חיבורים לאותו קובץ — אף עדכון אינו אובד', () async {
    // שני "חלונות": כל אחד עם חיבור משלו, כותבים לסירוגין לאותה רשימה.
    final dbA = UserStateDatabase.openAt(dbPath);
    final dbB = UserStateDatabase.openAt(dbPath);
    final a = UserStateListStore(database: dbA);
    final b = UserStateListStore(database: dbB);

    for (var i = 0; i < 20; i++) {
      final store = i.isEven ? a : b;
      await store.mutate(
        'history',
        'history',
        (current) => [...current, i],
      );
    }

    final fromA = await a.read('history', 'history');
    final fromB = await b.read('history', 'history');
    expect(fromA, List<int>.generate(20, (i) => i));
    expect(fromB, fromA);
    dbA.close();
    dbB.close();
  });

  test('כתיבה משדרת לחלונות אחרים ולא לעצמה', () async {
    final db = UserStateDatabase.openAt(dbPath);
    final store = UserStateListStore(database: db);
    WindowBus.instance.register();
    final mySlot = WindowBus.instance.slot!;

    // חלון מדומה במשבצת אחרת שרושם את ההודעות שקיבל.
    final peerPort = ReceivePort();
    final peerSlot = mySlot == 1 ? 2 : 1;
    ui.IsolateNameServer.registerPortWithName(
      peerPort.sendPort,
      '$_namespace.$peerSlot',
    );
    final received = <Map<String, dynamic>>[];
    peerPort.listen((message) {
      final map = message as Map;
      received.add(Map<String, dynamic>.from(map['body'] as Map));
      (map['reply'] as SendPort).send({'ok': true, 'result': true});
    });
    addTearDown(peerPort.close);

    final ownChanges = <UserStateListChange>[];
    final sub = store.changes.listen(ownChanges.add);
    addTearDown(sub.cancel);

    await store.write('history', 'history', [1]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received, hasLength(1));
    expect(received.single['type'], UserStateListStore.requestChanged);
    expect(received.single['box'], 'history');
    expect(received.single['origin'], mySlot);

    // ההודעה שחוזרת מהחלון האחר כן מזינה את הזרם המקומי...
    store.handleRequest({
      'type': UserStateListStore.requestChanged,
      'box': 'history',
      'key': 'history',
      'origin': peerSlot,
    });
    // ...אבל הודעה שמקורה בחלון הזה עצמו — לא.
    store.handleRequest({
      'type': UserStateListStore.requestChanged,
      'box': 'history',
      'key': 'history',
      'origin': mySlot,
    });
    await Future<void>.delayed(Duration.zero);
    expect(ownChanges, hasLength(1));
    expect(ownChanges.single.key, 'history');
    expect(ownChanges.single.origin, isNull);
    db.close();
  });

  group('חלונות Dart באותו isolate', () {
    tearDown(() => MultiViewMode.debugOverride = null);

    UserStateListRepository<int> repo(UserStateListStore store) =>
        UserStateListRepository<int>(
          boxName: 'history',
          key: 'history',
          fromJson: (json) => json['v'] as int,
          toJson: (value) => {'v': value},
          store: store,
        );

    test('כתיבה בחלון אחד מגיעה לשני, ולא לכותב עצמו', () async {
      MultiViewMode.debugOverride = true;
      final db = UserStateDatabase.openAt(dbPath);
      final store = UserStateListStore(database: db);
      final a = repo(store);
      final b = repo(store);
      var seenByA = 0;
      var seenByB = 0;
      final subA = a.remoteChanges.listen((_) => seenByA++);
      final subB = b.remoteChanges.listen((_) => seenByB++);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      await a.mutate((current) => [...current, 1]);
      await a.overwrite([2]);
      await a.clear();
      // כתיבה שאינה של אף חלון (למשל שחזור גיבוי) מגיעה לכולם.
      await store.write('history', 'history', const []);
      await Future<void>.delayed(Duration.zero);

      expect(seenByA, 1);
      expect(seenByB, 4);
      db.close();
    });

    test('בלי הדגל כתיבה מקומית אינה משודרת לעצמה', () async {
      final db = UserStateDatabase.openAt(dbPath);
      final store = UserStateListStore(database: db);
      final a = repo(store);
      final b = repo(store);
      var seen = 0;
      final subB = b.remoteChanges.listen((_) => seen++);
      addTearDown(subB.cancel);

      await a.mutate((current) => [...current, 1]);
      await Future<void>.delayed(Duration.zero);

      expect(seen, 0);
      db.close();
    });
  });
}
