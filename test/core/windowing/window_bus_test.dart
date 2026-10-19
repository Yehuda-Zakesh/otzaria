import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';

/// ⚠️ קידומת ייחודית לסוויטה. [IsolateNameServer] גלובלי לתהליך — בדיוק
/// הסיבה שהאפיק עובד — ושתי סוויטות שרצות תחת אותו `flutter test` תפסו את
/// אותן המשבצות והפילו זו את זו. בהרצה קרה 4 מתוך 6 נכשלו, ואז עברו
/// בהרצה חוזרת; סוויטה שנכשלת פעם בשש בלי סיבה נראית לעין מושתקת.
const String _namespace = 'otzaria.test.windowbus';

/// חלון מדומה שתופס משבצת ועונה לבקשות.
///
/// [WindowBus] הוא סינגלטון פר-isolate, ולכן בדיקה שצריכה **שני** חלונות
/// אינה יכולה להשתמש בו פעמיים. המחלקה הזו מדמה את הצד המרוחק ישירות מול
/// [IsolateNameServer] — אותו מנגנון בדיוק שהאפיק משתמש בו.
class _FakePeer {
  _FakePeer(this.slot, this.responder);

  final int slot;
  final Object? Function(Map<String, dynamic> request) responder;
  late final ReceivePort _port;

  bool register() {
    _port = ReceivePort();
    final ok = IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    if (!ok) {
      _port.close();
      return false;
    }
    _port.listen((message) {
      final map = message as Map;
      final reply = map['reply'] as SendPort;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      try {
        reply.send({'ok': true, 'result': responder(body)});
      } catch (e) {
        reply.send({'ok': false, 'error': '$e'});
      }
    });
    return true;
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    _port.close();
  }
}

/// משבצת רשומה שאין מאחוריה מאזין — מדמה חלון שקרס בלי לשחרר.
class _DeadSlot {
  _DeadSlot(this.slot);

  final int slot;
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    // נסגר מיד: השם נשאר רשום, אך אין מי שיענה.
    _port.close();
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping('$_namespace.$slot');
  }
}

void main() {
  setUp(() => WindowBus.namespace = _namespace);

  tearDown(() {
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
  });

  test('register תופס את המשבצת הפנויה הראשונה', () {
    expect(WindowBus.instance.register(), 1);
    expect(WindowBus.instance.slot, 1);
  });

  test('register מדלג על משבצת תפוסה', () {
    final peer = _FakePeer(1, (_) => null);
    expect(peer.register(), isTrue);
    addTearDown(peer.dispose);

    expect(WindowBus.instance.register(), 2);
  });

  test('register חוזר על אותה משבצת בקריאה שנייה, ולא תופס נוספת', () {
    expect(WindowBus.instance.register(), 1);
    expect(WindowBus.instance.register(), 1);
    // המשבצת השנייה נשארה פנויה.
    expect(
      IsolateNameServer.lookupPortByName('$_namespace.2'),
      isNull,
    );
  });

  test('כל המשבצות תפוסות מחזיר null ולא דורס רישום קיים', () {
    final peers = [
      for (var i = 1; i <= WindowBus.slotCount; i++) _FakePeer(i, (_) => null),
    ];
    for (final peer in peers) {
      expect(peer.register(), isTrue);
      addTearDown(peer.dispose);
    }

    expect(WindowBus.instance.register(), isNull);
    expect(WindowBus.instance.slot, isNull);
  });

  test('unregister משחרר את המשבצת לשימוש חוזר', () {
    expect(WindowBus.instance.register(), 1);
    WindowBus.instance.unregister();
    expect(WindowBus.instance.slot, isNull);

    // חלון אחר יכול עכשיו לתפוס אותה. בלי השחרור המשבצת הייתה אבודה.
    final peer = _FakePeer(1, (_) => null);
    expect(peer.register(), isTrue);
    addTearDown(peer.dispose);
  });

  test('חלון שנרשם אחרי הכנת היציאה משנה את קבוצת המשתתפים', () {
    WindowBus.instance.register();
    final first = _FakePeer(2, (_) => true);
    expect(first.register(), isTrue);
    addTearDown(first.dispose);
    final preparedPeers = WindowBus.instance.otherRegisteredSlots();

    final joined = _FakePeer(3, (_) => true);
    expect(joined.register(), isTrue);
    addTearDown(joined.dispose);

    expect(
      MultiWindowService.correctionQuitPeersUnchanged(preparedPeers),
      isFalse,
    );
  });

  test('request מחזיר את תשובת החלון השני', () async {
    final peer = _FakePeer(3, (request) => {'echo': request['value']});
    expect(peer.register(), isTrue);
    addTearDown(peer.dispose);

    WindowBus.instance.register();
    final result = await WindowBus.instance.request(3, {'value': 42});

    expect(result, isA<Map>());
    expect((result! as Map)['echo'], 42);
  });

  test('request למשבצת ריקה מחזיר null ואינו זורק', () async {
    WindowBus.instance.register();
    expect(await WindowBus.instance.request(4, const {'type': 'x'}), isNull);
  });

  test('שגיאה בצד המרוחק מוחזרת כ-null ואינה מתפשטת', () async {
    final peer = _FakePeer(2, (_) => throw StateError('boom'));
    expect(peer.register(), isTrue);
    addTearDown(peer.dispose);

    WindowBus.instance.register();
    expect(await WindowBus.instance.request(2, const {'type': 'x'}), isNull);
  });

  test('משבצת רשומה בלי מאזין נחתכת ב-timeout ואינה תולה את הקורא', () async {
    final dead = _DeadSlot(2);
    dead.register();
    addTearDown(dead.dispose);

    WindowBus.instance.register();
    final stopwatch = Stopwatch()..start();
    final result = await WindowBus.instance.request(
      2,
      const {'type': 'x'},
      timeout: const Duration(milliseconds: 200),
    );
    stopwatch.stop();

    expect(result, isNull);
    // ⚠️ זו הנקודה: בלי ה-timeout הקריאה לא הייתה חוזרת לעולם.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('onRequest של החלון עונה לפונים', () async {
    WindowBus.instance.register();
    WindowBus.instance.onRequest = (request) async => {
      'seen': request['type'],
    };

    // שולחים לעצמנו דרך אותו מנגנון שחלון אחר היה משתמש בו.
    final result = await WindowBus.instance.request(
      WindowBus.instance.slot!,
      const {'type': 'describe'},
    );
    expect((result! as Map)['seen'], 'describe');
  });

  test('peers מדלג על החלון עצמו ומחזיר רק מי שעונה', () async {
    final live = _FakePeer(
      2,
      (_) => {'title': 'בראשית', 'tabCount': 3},
    );
    expect(live.register(), isTrue);
    addTearDown(live.dispose);

    final dead = _DeadSlot(3);
    dead.register();
    addTearDown(dead.dispose);

    WindowBus.instance.register(); // תופס 1
    WindowBus.instance.onRequest = (_) async => {'title': 'אני', 'tabCount': 1};

    final found = await WindowBus.instance.peers(
      timeout: const Duration(milliseconds: 300),
    );

    // 2 עונה; 3 רשום אך מת; 1 הוא אנחנו ואינו נספר.
    expect(found.map((p) => p.slot), [2]);
    expect(found.single.title, 'בראשית');
    expect(found.single.tabCount, 3);
  });

  test('openUri נמסר לחלון היעד ומחזיר את תשובתו', () async {
    // ⚠️ המארח הוא המנקז היחיד של תור ההפעלות החיצוניות, ולכן הקישור מגיע
    // לחלון הפעיל האחרון רק דרך הבקשה הזו.
    String? delivered;
    final target = _FakePeer(2, (request) {
      delivered = request['uri'] as String?;
      return true;
    });
    expect(target.register(), isTrue);
    addTearDown(target.dispose);

    WindowBus.instance.register();
    final answer = await WindowBus.instance.request(2, {
      'type': MultiWindowService.requestOpenUri,
      'uri': 'otzaria://library',
    }, timeout: const Duration(milliseconds: 300));

    expect(delivered, 'otzaria://library');
    expect(answer, isTrue);
  });

  test('openUri למשבצת פנויה מחזיר null — המארח יטפל בעצמו', () async {
    WindowBus.instance.register();
    expect(
      await WindowBus.instance.request(3, {
        'type': MultiWindowService.requestOpenUri,
        'uri': 'otzaria://library',
      }, timeout: const Duration(milliseconds: 200)),
      isNull,
    );
  });

  test('peers מחזיר רשימה ריקה כשאין חלונות אחרים', () async {
    WindowBus.instance.register();
    expect(
      await WindowBus.instance.peers(
        timeout: const Duration(milliseconds: 200),
      ),
      isEmpty,
    );
  });
}
