import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'library_changes_store.dart';

/// מוריד את `library-changes.md` של releases שהוחלו, לפי התג ובלי פניית API.
/// הקובץ מועלה רק אחרי פרסום ה-release, ולכן 404 הוא "עדיין לא" — התג נשאר בתור.
class LibraryChangesFetcher {
  LibraryChangesFetcher({
    required this.store,
    http.Client Function()? clientFactory,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _now = now ?? DateTime.now;

  static const assetName = 'library-changes.md';

  /// עדכון שמדלג על יותר גרסאות מזה מציג רק את האחרונות.
  static const maxReleases = 10;

  /// תג שההערות שלו לא הופיעו בזמן הזה יורד מהתור.
  static const giveUpAfter = Duration(days: 14);

  // קובץ ההערות של עדכון ענק הוא מאות KB; גדול מזה אינו הקובץ הצפוי.
  static const _maxAssetBytes = 4 << 20;

  final LibraryChangesStore store;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;
  final Duration timeout;
  Future<void> _queueWrites = Future.value();
  Future<void> _fetches = Future.value();

  static Uri assetUrl(String releaseTag) => Uri.parse(
    'https://github.com/Otzaria/SeforimLibrary/releases/download/'
    '${Uri.encodeComponent(releaseTag)}/$assetName',
  );

  /// מוסיף לתור את [releaseTags] שאין להם עדיין הערות.
  Future<void> enqueue(Iterable<String> releaseTags) =>
      _serializeQueue(() => _enqueue(releaseTags));

  Future<void> _enqueue(Iterable<String> releaseTags) async {
    final queue = await store.readFetchQueue();
    final now = _now();
    for (final tag in releaseTags) {
      if (!LibraryChangesStore.isSafeTag(tag) || queue.containsKey(tag)) {
        continue;
      }
      if (await store.contains(tag)) continue;
      queue[tag] = now;
    }
    final newest = queue.keys.toList()..sort(LibraryChangesNote.newestTagFirst);
    await store.writeFetchQueue({
      for (final tag in newest.take(maxReleases)) tag: queue[tag]!,
    });
  }

  Future<void> _serializeQueue(Future<void> Function() operation) {
    final next = _queueWrites.then((_) => operation());
    _queueWrites = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  /// מנסה להוריד כל תג שבתור ומחזיר כמה נשמרו. לעולם אינו זורק.
  Future<int> fetchQueued() {
    final next = _fetches.then((_) => _fetchQueued());
    _fetches = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<int> _fetchQueued() async {
    final Map<String, DateTime> queue;
    try {
      queue = await store.readFetchQueue();
    } catch (e) {
      debugPrint('[LibraryChanges] queue read failed: $e');
      return 0;
    }
    if (queue.isEmpty) return 0;
    final initialTags = queue.keys.toSet();
    final now = _now();
    var saved = 0;
    final client = _clientFactory();
    try {
      for (final tag in queue.keys.toList()) {
        if (now.difference(queue[tag]!) > giveUpAfter) {
          queue.remove(tag);
          continue;
        }
        try {
          if (await store.contains(tag)) {
            queue.remove(tag);
            continue;
          }
          final response = await client.get(assetUrl(tag)).timeout(timeout);
          if (response.statusCode != 200) continue;
          final bytes = response.bodyBytes;
          if (bytes.length > _maxAssetBytes) {
            queue.remove(tag);
            continue;
          }
          final text = utf8.decode(bytes, allowMalformed: true);
          if (text.trim().isNotEmpty) {
            await store.writePending(tag, text);
            saved++;
          }
          queue.remove(tag);
        } catch (e) {
          debugPrint('[LibraryChanges] $tag failed: $e');
        }
      }
    } finally {
      client.close();
    }
    try {
      await _serializeQueue(() async {
        final current = await store.readFetchQueue();
        // הוספות לתור בזמן ההורדה חייבות להישאר לניסיון הבא.
        for (final tag in initialTags.difference(queue.keys.toSet())) {
          current.remove(tag);
        }
        await store.writeFetchQueue(current);
      });
    } catch (e) {
      debugPrint('[LibraryChanges] queue write failed: $e');
    }
    return saved;
  }
}
