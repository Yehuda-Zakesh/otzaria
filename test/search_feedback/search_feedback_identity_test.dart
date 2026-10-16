import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_identity.dart';
import 'package:otzaria/search_feedback/search_feedback_queue_lock.dart';
import 'package:pinenacl/ed25519.dart' as ed;

List<int> _hex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // RFC 8032, סעיף 7.1, וקטור בדיקה 1 (הודעה ריקה).
  const seedHex =
      '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
  const publicHex =
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
  const signatureHex =
      'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b';

  test('RFC 8032 test vector 1: public key, signature and keyId', () {
    final identity = SearchFeedbackIdentity.fromSeed(_hex(seedHex));
    expect(_toHex(identity.publicKey), publicHex);

    final signature = identity.sign(const []);
    expect(_toHex(base64.decode(signature)), signatureHex);
    expect(signature.endsWith('=='), isTrue, reason: 'standard padded base64');

    final keyId = identity.keyId;
    // ignore: avoid_print
    print('keyId(RFC 8032 #1) = $keyId');
    expect(keyId, hasLength(43));
    expect(keyId, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(keyId, 'If4x36FUomFia_hUBG_SJxt77UtqvkWqWId-9H-XIbk');
  });

  test('signature verifies over the exact UTF-8 body bytes', () {
    final identity = SearchFeedbackIdentity.generate();
    final body = utf8.encode('{"a":"\\u05d0"}');
    final signature = base64.decode(identity.sign(body));
    final verified = ed.VerifyKey(identity.publicKey).verify(
      signature: ed.Signature(signature),
      message: body,
    );
    expect(verified, isTrue);
  });

  test('store round-trips registration and blocked state', () async {
    final dir = await Directory.systemTemp.createTemp('sf_identity');
    addTearDown(() => dir.delete(recursive: true));
    final store = SearchFeedbackIdentityStore(() async => dir);
    expect(await store.load(), isNull);

    final identity = SearchFeedbackIdentity.generate()..blocked = true;
    identity.registeredKeyId = identity.keyId;
    await store.save(identity);

    final loaded = (await store.load())!;
    expect(loaded.keyId, identity.keyId);
    expect(loaded.isRegistered, isTrue);
    expect(loaded.blocked, isTrue);

    await store.delete();
    expect(await store.load(), isNull);
  });

  test('a corrupt key file reads as no identity', () {
    expect(SearchFeedbackIdentity.tryParse('not json'), isNull);
    expect(SearchFeedbackIdentity.tryParse('{"seed":"AAAA"}'), isNull);
  });

  group('loadOrCreate', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sf_identity');
      path = '${dir.path}/${SearchFeedbackIdentityStore.fileName}';
    });
    tearDown(() => dir.delete(recursive: true));

    test('invalidation while waiting for the lock prevents writing', () async {
      final held = await SearchFeedbackQueueLock.acquire('$path.lock');
      final checked = Completer<void>();
      var current = true;
      final creating =
          SearchFeedbackIdentityStore(
            () async => dir,
          ).loadOrCreate(
            List.filled(32, 7),
            isCurrent: () {
              if (!checked.isCompleted) checked.complete();
              return current;
            },
          );
      await checked.future;
      current = false;
      await held.release();
      expect(await creating, isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test(
      'a throwing validity check refuses to write and releases the lock',
      () async {
        var calls = 0;
        final result =
            await SearchFeedbackIdentityStore(
              () async => dir,
            ).loadOrCreate(
              List.filled(32, 7),
              isCurrent: () {
                if (++calls > 1) throw StateError('consent unreadable');
                return true;
              },
            );
        expect(result, isNull);
        expect(File(path).existsSync(), isFalse);
        final lock = await SearchFeedbackQueueLock.acquire('$path.lock');
        await lock.release();
      },
    );
  });
}
