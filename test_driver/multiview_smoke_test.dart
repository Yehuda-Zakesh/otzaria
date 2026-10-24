// מריץ את test_driver/multiview_smoke.dart. ב-Windows בלבד, ובמצב נייד
// (portable.marker ליד ה-exe) כדי לא לגעת בפרופיל ובמופע היחיד של המשתמש:
//   flutter drive -d windows -t test_driver/multiview_smoke.dart --dart-define=SENTRY_DSN=
import 'dart:convert';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  late FlutterDriver driver;

  Future<Map<String, Object?>> send(
    String type, [
    Map<String, Object?> args = const {},
  ]) async {
    final response = await driver.requestData(
      jsonEncode({'type': type, ...args}),
      timeout: const Duration(minutes: 2),
    );
    final data = jsonDecode(response) as Map<String, Object?>;
    if (data.containsKey('error')) {
      fail('$type: ${data['error']}\nstate: ${data['state']}');
    }
    return data;
  }

  Map<String, Object?> stateOf(Map<String, Object?> r) =>
      r['state']! as Map<String, Object?>;
  List<Map<String, Object?>> viewsOf(Map<String, Object?> r) => [
    for (final v in stateOf(r)['views']! as List) v as Map<String, Object?>,
  ];

  setUpAll(() async {
    driver = await FlutterDriver.connect();
  });

  tearDownAll(() async {
    await driver.close();
  });

  test('multiview: open, move tabs, close, cap', () async {
    final ready = stateOf(await send('ready'));
    expect(ready['multiview'], isTrue, reason: '$ready');
    expect(ready['ownerInstalled'], isTrue);
    expect(ready['opener'], 'ViewWindowOpener');
    expect(ready['views'], isEmpty);

    // חלון ריק שני, אמיתי וגלוי.
    var r = await send('open_empty');
    expect(r['ok'], isTrue, reason: '$r');
    var views = viewsOf(r);
    expect(views, hasLength(1));
    expect(views.single['hasHwnd'], isTrue);
    expect(views.single['visible'], isTrue);
    final emptySlot = views.single['slot']! as int;

    // כרטיסיה מהראשי לחלון חדש.
    r = await send('move_main_tab_to_new_window');
    expect(r['ok'], isTrue, reason: '$r');
    views = viewsOf(r);
    expect(views, hasLength(2));
    final tabView = views.firstWhere((v) => v['slot'] != emptySlot);
    expect(tabView['toolTabs'], ['builtin.measurements']);
    expect(stateOf(r)['mainToolTabs'], isEmpty);

    // ובחזרה מהחלון אל הראשי.
    final tabSlot = tabView['slot']! as int;
    r = await send('send_view_tab_to_main', {'slot': tabSlot});
    expect(r['ok'], isTrue, reason: '$r');
    expect(stateOf(r)['mainToolTabs'], ['builtin.measurements']);
    expect(
      viewsOf(r).firstWhere((v) => v['slot'] == tabSlot)['toolTabs'],
      isEmpty,
    );

    // סגירה ב-WM_CLOSE: החלון נהרס, הראשי ממשיך לחיות.
    r = await send('close_view', {'slot': tabSlot});
    r = await send('close_view', {'slot': emptySlot});
    expect(viewsOf(r), isEmpty);
    expect(stateOf(r)['mainReady'], isTrue);
    expect(stateOf(r)['mainVisible'], isTrue);
    expect(stateOf(r)['mainToolTabs'], ['builtin.measurements']);

    // תקרת החלונות: הראשי נספר, ופתיחה מעבר לה נכשלת.
    r = await send('fill_to_cap');
    final max = stateOf(r)['maxWindows']! as int;
    expect(r['opened'], max - 1, reason: '$r');
    expect(r['pastCap'], isFalse);
    expect(viewsOf(r), hasLength(max - 1));

    r = await send('close_all_views');
    expect(viewsOf(r), isEmpty);
    expect(stateOf(r)['mainReady'], isTrue);
    expect(stateOf(r)['mainVisible'], isTrue);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
