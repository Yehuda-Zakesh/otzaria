import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../support/calendar_alerts_fakes.dart';

/// חלונות אמיתיים הם isolates באותו תהליך; כאן ה-isolate הראשי הוא הבעלים,
/// וכל "חלון משני" הוא isolate עם הגדרות משלו, ורק האפיק מחבר ביניהם.
const String _namespace = 'otzaria.test.calendaralerts.isolates';

const _eventsKey = SettingsRepository.keyCalendarEvents;

Future<void> _windowMain(List<Object> args) async {
  WindowBus.namespace = _namespace;
  final ready = args[0] as SendPort;
  MultiWindowService.debugSupportedOverride = true;
  await Settings.init(cacheProvider: MemoryCacheProvider());
  final client = RemoteCalendarAlertsClient();
  final slot = WindowBus.instance.register();
  WindowBus.instance.onRequest = (request) async {
    final handled = await client.handleBusMessage(request);
    if (handled != null) return handled;
    switch (request['type']) {
      case 'test.send':
        final ack = await client.send(
          request['op'] as String,
          Map<String, Object?>.from(request['args'] as Map),
        );
        return {'ok': ack.ok, 'failure': ack.failure?.name};
      case 'test.state':
        return {
          'revision': client.appliedRevision,
          'events': Settings.getValue<String>(_eventsKey),
        };
      case 'test.sendRaw':
        // כמו שחלון בגרסה הקודמת היה משדר את הרשימה כולה אחרי עריכה.
        return WindowBus.instance.requestPort(
          WindowBus.instance.ownerPort!,
          Map<String, dynamic>.from(request['body'] as Map),
        );
      case SettingsSync.requestChanged:
        return SettingsSync.instance.handleRequest(request);
    }
    return null;
  };
  ready.send(slot);
}

/// רישום מזהי תוסף שקריאתו איטית, כדי ששני רישומים במקביל ייפגשו.
class _SlowPluginIds implements PluginNotificationIdStore {
  final ids = <String, List<int>>{};

  @override
  Future<List<int>> read(String pluginId) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return [...?ids[pluginId]];
  }

  @override
  Future<void> write(String pluginId, List<int> value) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ids[pluginId] = [...value];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  final now = DateTime(2026, 10, 20, 9);
  final isolates = <Isolate>[];
  late WindowsLikeNotifications notifications;
  late _SlowPluginIds pluginIds;
  late CalendarAlertsOwner owner;
  // החלונות כאן הם isolates באותה group; בין חלונות אמיתיים SendPort מחמיר.
  final unsendable = <Object?>[];

  Future<int> spawnWindow() async {
    final ready = ReceivePort();
    isolates.add(await Isolate.spawn(_windowMain, [ready.sendPort]));
    return await ready.first as int;
  }

  Future<Object?> callRaw(int slot, Map<String, dynamic> body) =>
      WindowBus.instance.request(
        slot,
        body,
        timeout: const Duration(seconds: 15),
      );

  Future<Map> call(int slot, Map<String, dynamic> body) async =>
      (await callRaw(slot, body))! as Map;

  Future<Map> send(int slot, String op, Map<String, Object?> args) =>
      call(slot, {'type': 'test.send', 'op': op, 'args': args});

  Map<String, Object?> eventJson(String id, {String? source, int day = 25}) =>
      jsonDecode(
            jsonEncode(futureEvent(id, day: day, icsSourceId: source).toJson()),
          )
          as Map<String, Object?>;

  List<Object?> storedIds() => [
    for (final e in jsonDecode(Settings.getValue<String>(_eventsKey)!) as List)
      (e as Map)['id'],
  ];

  /// השידורים אסינכרוניים; ממתינים עד שהחלון מגיע ל-revision של הבעלים.
  Future<Map> converged(int slot) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final state = await call(slot, const {'type': 'test.state'});
      if (state['revision'] == owner.revision ||
          DateTime.now().isAfter(deadline)) {
        return state;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = _namespace;
    await Settings.init(cacheProvider: MemoryCacheProvider());
    notifications = WindowsLikeNotifications();
    pluginIds = _SlowPluginIds();
    owner = CalendarAlertsOwner(
      notifications: notifications,
      pluginIds: pluginIds,
      pluginEvents: () async => const [],
      now: () => now,
      broadcast: (message) {
        if (!isCrossGroupSendable(message)) unsendable.add(message);
        WindowBus.instance.broadcast(message);
      },
      dedupeDuplicates: false,
    );
    expect(WindowBus.instance.register(asOwner: true), isNotNull);
    WindowBus.instance.onRequest = (request) async {
      switch (request['type']) {
        case CalendarAlertsOwner.requestCommand:
          if (!isCrossGroupSendable(request)) unsendable.add(request);
          final ack = await owner.handleBusRequest(request);
          if (!isCrossGroupSendable(ack)) unsendable.add(ack);
          return ack;
        case SettingsSync.requestChanged:
          return SettingsSync.instance.handleRequest(request);
      }
      return null;
    };
  });

  tearDown(() async {
    await owner.idle;
    expect(unsendable, isEmpty);
    unsendable.clear();
    for (final isolate in isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    isolates.clear();
    owner.dispose();
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    IsolateNameServer.removePortNameMapping('$_namespace.owner');
    SettingsSync.instance.dispose();
    MultiWindowService.debugSupportedOverride = null;
    WindowBus.namespace = 'otzaria.window';
  });

  test(
    '(א) מחיקה מחלון משני בזמן רענון ICS בבעלים: האירוע אינו חוזר',
    () async {
      await Settings.setValue<String>(
        _eventsKey,
        jsonEncode([eventJson('e1'), eventJson('ics1', source: 's')]),
      );
      await Settings.setValue<String>(
        SettingsRepository.keyCalendarIcsSubscriptions,
        jsonEncode([
          {'id': 's', 'name': 'מנוי', 'url': 'https://example.com/a.ics'},
        ]),
      );
      final window = await spawnWindow();
      await owner.restoreIfNeeded();
      expect(notifications.present, {reminderId('e1'), reminderId('ics1')});

      final blocked = Completer<void>();
      final gate = Completer<void>();
      notifications.onSchedule = (_) {
        notifications.scheduleGate = gate;
        if (!blocked.isCompleted) blocked.complete();
      };
      final refresh = await owner.execute('replaceSourceEvents', {
        'kind': 'ics',
        'sourceId': 's',
        'events': [
          eventJson('ics1', source: 's', day: 26),
          eventJson('ics2', source: 's'),
        ],
      });
      expect(refresh['ok'], isTrue);
      await blocked.future;

      final deleted = await send(window, 'deleteEvent', {'id': 'e1'});
      expect(deleted['ok'], isTrue, reason: 'התור אינו ממתין לתזמון');

      gate.complete();
      await owner.idle;

      expect(storedIds(), unorderedEquals(['ics1', 'ics2']));
      expect(notifications.everyIdAtMostOnce, isTrue);
      final plan = {reminderId('ics1'), reminderId('ics2')};
      expect(notifications.present, plan);
      expect(
        decodeLedger(
          Settings.getValue<String>(CalendarAlertsKeys.ledger)!,
        ).toSet(),
        plan,
      );
      final state = await converged(window);
      expect(state['revision'], owner.revision);
      expect(state['events'], Settings.getValue<String>(_eventsKey));
    },
  );

  test('(ב) שני חלונות משניים עורכים במקביל, ושתי העריכות נשמרות', () async {
    final first = await spawnWindow();
    final second = await spawnWindow();

    final results = await Future.wait([
      send(first, 'upsertEvent', {'event': eventJson('from-1')}),
      send(second, 'upsertEvent', {'event': eventJson('from-2')}),
    ]);
    await owner.idle;

    expect(results.map((r) => r['ok']), [true, true]);
    expect(storedIds(), unorderedEquals(['from-1', 'from-2']));
    for (final window in [first, second]) {
      final state = await converged(window);
      expect(state['revision'], owner.revision);
      expect(state['events'], Settings.getValue<String>(_eventsKey));
    }
    expect(notifications.present, {
      reminderId('from-1'),
      reminderId('from-2'),
    });
  });

  test('(ג) settingChanged ישן של רשימת האירועים נדחה', () async {
    await Settings.setValue<String>(
      _eventsKey,
      jsonEncode([eventJson('e1')]),
    );
    final window = await spawnWindow();
    await send(window, 'deleteEvent', {'id': 'e1'});
    await owner.idle;

    final stale = await callRaw(window, {
      'type': 'test.sendRaw',
      'body': {
        'type': SettingsSync.requestChanged,
        'key': _eventsKey,
        'value': jsonEncode([eventJson('e1')]),
      },
    });

    expect(stale, isFalse);
    expect(storedIds(), isEmpty);
    await owner.idle;
    expect(notifications.present, isEmpty);
  });

  test('(ד) שער עלייה תקוע: האישור חוזר, והתזמון קורה פעם אחת אחריו', () async {
    notifications.initGate = Completer<void>();
    final window = await spawnWindow();

    final ack = await send(window, 'upsertEvent', {
      'event': eventJson('a'),
    }).timeout(const Duration(seconds: 5));
    await send(window, 'upsertEvent', {'event': eventJson('a', day: 26)});
    expect(ack['ok'], isTrue);
    expect(notifications.scheduled, isEmpty);

    notifications.initGate!.complete();
    await owner.idle;

    expect(
      notifications.scheduled.where((s) => s.id == reminderId('a')),
      hasLength(1),
    );
    expect(notifications.present, {reminderId('a')});
  });

  test('(ו) שני גשרי תוספים רושמים מזהים במקביל, ושניהם נשמרים', () async {
    final first = await spawnWindow();
    final second = await spawnWindow();
    final at = now.add(const Duration(hours: 2)).toIso8601String();

    final results = await Future.wait([
      for (final (window, id) in [(first, 11), (second, 22)])
        send(window, 'pluginSchedule', {
          'pluginId': 'p',
          'id': id,
          'title': 't',
          'body': 'b',
          'at': at,
        }),
    ]);

    expect(results.map((r) => r['ok']), [true, true]);
    expect(pluginIds.ids['p'], unorderedEquals([11, 22]));
    expect(notifications.present, {11, 22});
  });

  test('stateChanged ישן נזרק בחלון המשני', () async {
    final window = await spawnWindow();
    await send(window, 'upsertEvent', {'event': eventJson('fresh')});
    final current = await converged(window);

    final handled = await callRaw(window, {
      'type': CalendarAlertsOwner.requestStateChanged,
      'epoch': owner.epoch,
      'revision': 0,
      'values': {
        _eventsKey: jsonEncode([eventJson('stale')]),
      },
    });

    expect(handled, isFalse);
    final after = await call(window, const {'type': 'test.state'});
    expect(after['events'], current['events']);
    expect(after['revision'], current['revision']);
  });
}
