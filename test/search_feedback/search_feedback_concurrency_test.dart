import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/search_feedback/search_feedback_identity.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/search_feedback/search_feedback_queue.dart';
import 'package:otzaria/search_feedback/search_feedback_sender.dart';
import 'search_feedback_test_support.dart';

class NoTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

void main() {
  test(
    'a sender must discover events queued later by another writer',
    () async {
      final dir = await Directory.systemTemp.createTemp('audit1758_discovery_');
      addTearDown(() => dir.delete(recursive: true));
      final consent = MemoryConsentPersistence()
        ..state = 'granted'
        ..version = 1;
      final posts = <http.Request>[];
      SearchFeedbackService service() => SearchFeedbackService(
        storageDirectory: () async => dir,
        consentPersistence: consent,
        clock: () => kStart.add(const Duration(seconds: 5)),
        buildAllowsSending: true,
        sendingAllowed: () => true,
        appVersion: () => '1.2.3',
        platform: () => 'windows',
        osVersion: () => '10.0',
        locale: () => 'he',
        timerFactory: (_, _) => NoTimer(),
        client: MockClient((r) async {
          posts.add(r);
          if (r.url.path.endsWith('/register')) {
            final b = jsonDecode(r.body) as Map;
            return http.Response(
              jsonEncode({
                'keyId': SearchFeedbackIdentity.keyIdOf(
                  base64.decode(b['publicKey'] as String),
                ),
              }),
              200,
            );
          }
          return http.Response('{"accepted":1}', 200);
        }),
        baseUrl: Uri.parse('https://example.test'),
      );
      final primary = service();
      await primary.flush(); // loads empty shared directory
      final secondary = service();
      secondary.recordSearch(searchContext());
      await secondary.whenQueued();
      expect(
        dir.listSync().where((f) => f.path.endsWith('.jsonl')),
        isNotEmpty,
      );
      for (var i = 0; i < 3; i++) {
        await primary.flush();
      }
      expect(posts.where((p) => p.url.path.endsWith('/events')), hasLength(1));
    },
  );
  test('shared queue caps apply globally across writers', () async {
    final dir = await Directory.systemTemp.createTemp('audit1758_caps_');
    addTearDown(() => dir.delete(recursive: true));
    var tick = 0;
    final writers = List.generate(
      3,
      (_) => SearchFeedbackQueue(
        () async => dir,
        clock: () => kStart.add(Duration(microseconds: tick++)),
        maxEvents: 4,
        segmentEvents: 2,
      ),
    );
    for (final w in writers) {
      await w.load();
    }
    for (final w in writers) {
      for (var i = 0; i < 4; i++) {
        await w.append(
          {'eventId': 'event_caps_$tick', 'n': i},
          {'app': 'otzaria'},
        );
      }
    }
    final reader = SearchFeedbackQueue(
      () async => dir,
      clock: () => kStart,
      maxEvents: 4,
      segmentEvents: 2,
    );
    await reader.load();
    expect(reader.eventCount, lessThanOrEqualTo(4));
  });
  for (final platform in ['android', 'ios']) {
    test(
      '$platform never collects or sends even with sending override',
      () async {
        final dir = await Directory.systemTemp.createTemp('sf_platform');
        addTearDown(() => dir.delete(recursive: true));
        final consent = MemoryConsentPersistence()
          ..state = 'granted'
          ..version = 1;
        var posts = 0;
        final service = SearchFeedbackService(
          storageDirectory: () async => dir,
          consentPersistence: consent,
          platform: () => platform,
          buildAllowsSending: true,
          sendingAllowed: () => true,
          timerFactory: (_, _) => NoTimer(),
          client: MockClient((_) async {
            posts++;
            return http.Response('{}', 200);
          }),
        );
        expect(service.isCollecting, false);
        service.recordSearch(searchContext());
        await service.whenQueued();
        await service.grant();
        await service.flush();
        expect(posts, 0);
        expect(await dir.list().toList(), isEmpty);
      },
    );
  }
  test('revoke during asynchronous signing prevents HTTP', () async {
    var allowed = true;
    var posts = 0;
    final sender = SearchFeedbackSender(
      client: () => MockClient((_) async {
        posts++;
        return http.Response('{}', 200);
      }),
      clock: () => kStart,
      baseUrl: Uri.parse('https://example.test'),
    );
    final sending = sender.sendEvents(
      identity: SearchFeedbackIdentity.fromSeed(List.filled(32, 1)),
      body: '{"events":[]}',
      appVersion: '1',
      canSend: () => allowed,
    );
    allowed = false;
    expect((await sending).kind, SearchFeedbackOutcomeKind.retryLater);
    expect(posts, 0);
  });
  test('stale consent cannot enqueue after another instance revokes', () async {
    final dir = await Directory.systemTemp.createTemp('sf_stale_consent');
    addTearDown(() => dir.delete(recursive: true));
    SearchFeedbackService service(MemoryConsentPersistence consent) =>
        SearchFeedbackService(
          storageDirectory: () async => dir,
          consentPersistence: consent,
          platform: () => 'windows',
          buildAllowsSending: false,
          timerFactory: (_, _) => NoTimer(),
          appVersion: () => '1.2.3',
          osVersion: () => '10.0',
          locale: () => 'he',
        );
    final primaryConsent = MemoryConsentPersistence()
      ..state = 'granted'
      ..version = 1;
    final secondaryConsent = MemoryConsentPersistence()
      ..state = 'granted'
      ..version = 1;
    final primary = service(primaryConsent);
    final secondary = service(secondaryConsent);
    await primary.revoke();
    secondary.recordSearch(searchContext());
    await secondary.whenQueued();
    final segments = dir
        .listSync()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList();
    expect(
      segments,
      isEmpty,
      reason: 'revoke completed; secondary consent may still be stale',
    );
  });
}
