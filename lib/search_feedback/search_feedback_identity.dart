import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:otzaria/search_feedback/search_feedback_queue_lock.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/ed25519.dart' as ed;

/// זהות אנונימית של ההתקנה: זוג מפתחות ed25519 ומצב הרישום מול השרת.
class SearchFeedbackIdentity {
  SearchFeedbackIdentity.fromSeed(
    List<int> seed, {
    this.registeredKeyId,
    this.blocked = false,
  }) : _seed = Uint8List.fromList(seed),
       _signingKey = ed.SigningKey.fromSeed(Uint8List.fromList(seed)) {
    if (seed.length != seedLength) {
      throw const FormatException('seed must be 32 bytes');
    }
  }

  /// זהות חדשה מזרע אקראי.
  factory SearchFeedbackIdentity.generate([Random? random]) {
    final rng = random ?? Random.secure();
    return SearchFeedbackIdentity.fromSeed([
      for (var i = 0; i < seedLength; i++) rng.nextInt(256),
    ]);
  }

  static const int seedLength = 32;

  final Uint8List _seed;
  final ed.SigningKey _signingKey;

  /// ה-keyId שהשרת אישר ברישום; null = טרם נרשם.
  String? registeredKeyId;

  /// השרת חסם את המפתח — לא אוספים ולא שולחים עם מפתח זה.
  bool blocked;

  bool get isRegistered => registeredKeyId == keyId;

  Uint8List get publicKey => _signingKey.verifyKey.asTypedList;

  String get publicKeyBase64 => base64.encode(publicKey);

  String get keyId => keyIdOf(publicKey);

  /// base64url בלי ריפוד של SHA-256 על המפתח הציבורי הגולמי (43 תווים).
  static String keyIdOf(List<int> publicKey) =>
      base64Url.encode(sha256.convert(publicKey).bytes).replaceAll('=', '');

  /// חתימה (base64 רגיל, עם ריפוד) על הבתים המדויקים של [message].
  String sign(List<int> message) => base64.encode(
    _signingKey.sign(Uint8List.fromList(message)).signature.asTypedList,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'seed': base64.encode(_seed),
    'registeredKeyId': registeredKeyId,
    'blocked': blocked,
  };

  /// null על קובץ פגום.
  static SearchFeedbackIdentity? tryParse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final seed = base64.decode(json['seed'] as String);
      if (seed.length != seedLength) return null;
      return SearchFeedbackIdentity.fromSeed(
        seed,
        registeredKeyId: json['registeredKeyId'] as String?,
        blocked: json['blocked'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// שמירת הזהות כקובץ בתיקיית נתוני האפליקציה (לא בהגדרות).
class SearchFeedbackIdentityStore {
  SearchFeedbackIdentityStore(this._directory);

  static const String fileName = 'installation_key.json';

  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File(p.join((await _directory()).path, fileName));

  Future<SearchFeedbackIdentity?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    return _parseIdentity(text);
  }

  /// כתיבה אטומית תחת נעילה בין תהליכים.
  Future<void> save(SearchFeedbackIdentity identity) async {
    final path = (await _file()).path;
    final text = jsonEncode(identity.toJson());
    await Isolate.run(() => _locked(path, () => _writeIdentity(path, text)));
  }

  /// הזהות הקיימת (גם חסומה) או חדשה מ-[seed]; נעילה בין תהליכים, בלי רשת.
  /// null = הקובץ פגום (נשמר כמו שהוא), או ש-[isCurrent] נכשל.
  Future<SearchFeedbackIdentity?> loadOrCreate(
    List<int> seed, {
    required bool Function() isCurrent,
  }) async {
    final path = (await _file()).path;
    if (!isCurrent()) return null;
    // ה-isolate אינו רואה את מצב השירות: הוא שואל כאן שוב אחרי שהשיג את הנעילה.
    final approvals = ReceivePort()
      ..listen((reply) => (reply as SendPort).send(_approves(isCurrent)));
    final port = approvals.sendPort;
    try {
      return await _runLoadOrCreate(path, seed, port);
    } finally {
      approvals.close();
    }
  }

  /// בדיקה שנכשלה אינה אישור; בלי תשובה העובד היה ממתין עם הנעילה לנצח.
  static bool _approves(bool Function() isCurrent) {
    try {
      return isCurrent();
    } catch (_) {
      return false;
    }
  }

  Future<void> delete() async {
    final file = await _file();
    for (final target in [file, File('${file.path}.tmp')]) {
      if (await target.exists()) await target.delete();
    }
  }
}

Future<SearchFeedbackIdentity?> _parseIdentity(String text) =>
    Isolate.run(() => SearchFeedbackIdentity.tryParse(text));

/// כתיבה לקובץ זמני והחלפה, כדי שקריסה באמצע לא תשאיר קובץ חתוך.
Future<void> _writeIdentity(String path, String text) async {
  final temp = File('$path.tmp');
  await temp.writeAsString(text, flush: true);
  await temp.rename(path);
}

/// כל כתיבה של הזהות עוברת כאן, כדי שחלון או תהליך אחר לא ידרוס אותה.
Future<T> _locked<T>(String path, Future<T> Function() action) async {
  await File(path).parent.create(recursive: true);
  final lock = await SearchFeedbackQueueLock.acquire('$path.lock');
  try {
    return await action();
  } finally {
    await lock.release();
  }
}

// פונקציה עליונה, כדי שה-closure לא ילכוד את isCurrent (שאינו ניתן לשליחה).
Future<SearchFeedbackIdentity?> _runLoadOrCreate(
  String path,
  List<int> seed,
  SendPort approvals,
) => Isolate.run(() => _loadOrCreateLocked(path, seed, approvals));

Future<SearchFeedbackIdentity?> _loadOrCreateLocked(
  String path,
  List<int> seed,
  SendPort approvals,
) => _locked(path, () async {
  final file = File(path);
  if (await file.exists()) {
    // קובץ פגום אינו נדרס: ייתכן שהיה בו מפתח חסום.
    return SearchFeedbackIdentity.tryParse(await file.readAsString());
  }
  final answer = ReceivePort();
  approvals.send(answer.sendPort);
  if (await answer.first != true) return null;
  final created = SearchFeedbackIdentity.fromSeed(seed);
  await _writeIdentity(path, jsonEncode(created.toJson()));
  return created;
});
