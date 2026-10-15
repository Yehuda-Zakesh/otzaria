import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_fetcher.dart';
import 'package:otzaria/library_update/changes_notes/library_changes_store.dart';

void main() {
  late Directory root;
  late LibraryChangesStore store;
  var now = DateTime.utc(2026, 10, 13);

  setUp(() {
    root = Directory.systemTemp.createTempSync('library_changes_fetch_');
    store = LibraryChangesStore(dataRootProvider: () async => root.path);
    now = DateTime.utc(2026, 10, 13);
  });

  tearDown(() => root.deleteSync(recursive: true));

  LibraryChangesFetcher fetcher(MockClientHandler handler) =>
      LibraryChangesFetcher(
        store: store,
        clientFactory: () => MockClient(handler),
        now: () => now,
        timeout: const Duration(milliseconds: 200),
      );

  test('כתובת ישירה לנכס לפי התג, בלי API', () {
    expect(
      LibraryChangesFetcher.assetUrl('v33-20261020000000').toString(),
      'https://github.com/Otzaria/SeforimLibrary/releases/download/'
      'v33-20261020000000/library-changes.md',
    );
  });

  test('404 ו-timeout נשארים בתור; 200 נשמר ויוצא מהתור', () async {
    final requested = <String>[];
    final f = fetcher((request) async {
      final url = request.url.toString();
      requested.add(url);
      if (url.contains('v33')) return http.Response('', 404);
      if (url.contains('v34')) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      return http.Response.bytes(utf8.encode('# גרסת ספרייה 35\n'), 200);
    });
    await f.enqueue([
      'v33-20261020000000',
      'v34-20261101000000',
      'v35-20261110000000',
    ]);

    expect(await f.fetchQueued(), 1);
    expect(requested, everyElement(startsWith('https://github.com/')));
    final notes = await store.readPending();
    expect(notes.single.releaseTag, 'v35-20261110000000');
    expect(notes.single.markdown, '# גרסת ספרייה 35\n');
    expect((await store.readFetchQueue()).keys.toSet(), {
      'v33-20261020000000',
      'v34-20261101000000',
    });
  });

  test('ניסיון חוזר אחרי שהקובץ פורסם', () async {
    var published = false;
    final f = fetcher(
      (_) async => published
          ? http.Response.bytes(utf8.encode('# 33'), 200)
          : http.Response('', 404),
    );
    await f.enqueue(['v33-20261020000000']);
    expect(await f.fetchQueued(), 0);
    published = true;
    expect(await f.fetchQueued(), 1);
    expect(await store.readFetchQueue(), isEmpty);
  });

  test('מוותרים אחרי 14 יום', () async {
    var calls = 0;
    final f = fetcher((_) async {
      calls++;
      return http.Response('', 404);
    });
    await f.enqueue(['v33-20261020000000']);
    now = now.add(const Duration(days: 15));
    expect(await f.fetchQueued(), 0);
    expect(calls, 0);
    expect(await store.readFetchQueue(), isEmpty);
  });

  test('תג שכבר יש לו הערות אינו נכנס לתור; תג לא בטוח נדחה', () async {
    await store.writePending('v35-20261110000000', 'קיים');
    final f = fetcher((_) async => http.Response('', 404));
    await f.enqueue(['v35-20261110000000', '../x']);
    expect(await store.readFetchQueue(), isEmpty);
  });

  test('התור מוגבל ל-maxReleases החדשים', () async {
    final f = fetcher((_) async => http.Response('', 404));
    await f.enqueue([for (var v = 40; v < 60; v++) 'v$v-t']);
    final queue = await store.readFetchQueue();
    expect(queue, hasLength(LibraryChangesFetcher.maxReleases));
    expect(queue.keys, contains('v59-t'));
    expect(queue.keys, isNot(contains('v40-t')));
  });

  test('כשל רשת אינו זורק', () async {
    final f = fetcher((_) async => throw const SocketException('offline'));
    await f.enqueue(['v33-20261020000000']);
    expect(await f.fetchQueued(), 0);
    expect(await store.readFetchQueue(), hasLength(1));
  });
}
