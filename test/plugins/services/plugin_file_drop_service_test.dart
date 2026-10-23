import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PluginFileDropService service;

  setUp(() => service = PluginFileDropService());

  WindowsFileDropEvent event({
    List<String> paths = const [],
    double x = 0,
    double y = 0,
  }) => WindowsFileDropEvent(paths: paths, x: x, y: y);

  test('גרירה קובעת את הגרירה הפעילה עם הנתיבים והמיקום', () {
    service.handleDrag(event(paths: ['C:/a.otzplugin'], x: 40, y: 60));

    expect(service.drag.value?.paths, ['C:/a.otzplugin']);
    expect(service.drag.value?.physicalPosition, const Offset(40, 60));
  });

  test('over חסר-נתיבים שומר את הנתיבים שהתקבלו ב-enter', () {
    service.handleDrag(event(paths: ['C:/a.otzplugin'], x: 10, y: 10));
    service.handleDrag(event(x: 80, y: 90));

    expect(service.drag.value?.paths, ['C:/a.otzplugin']);
    expect(service.drag.value?.physicalPosition, const Offset(80, 90));
  });

  test('גרירה מוחזרת כמאושרת רק כשאזור כלשהו מוכן לקלוט', () {
    expect(service.handleDrag(event(paths: ['C:/a.otzplugin'])), isFalse);

    final zone = Object();
    service.setZoneAccepting(zone, true);
    expect(service.handleDrag(event(paths: ['C:/a.otzplugin'])), isTrue);

    service.setZoneAccepting(zone, false);
    expect(service.handleDrag(event(paths: ['C:/a.otzplugin'])), isFalse);
  });

  test('leave מנקה את הגרירה', () {
    service.handleDrag(event(paths: ['C:/a.otzplugin']));
    service.handleLeave();

    expect(service.drag.value, isNull);
  });

  test('drop משדר את הנתיבים ומנקה את הגרירה', () async {
    service.handleDrag(event(paths: ['C:/a.otzplugin']));

    final dropped = expectLater(
      service.drops,
      emits(
        isA<PluginFileDrag>()
            .having((d) => d.paths, 'paths', ['C:/a.otzplugin'])
            .having((d) => d.physicalPosition, 'position', const Offset(5, 7)),
      ),
    );
    await service.handleDrop(event(paths: ['C:/a.otzplugin'], x: 5, y: 7));

    expect(service.drag.value, isNull);
    await dropped;
  });

  test('גרירת קבצים וירטואליים ללא נתיבים אינה מפילה', () {
    service.handleDrag(event());

    expect(service.drag.value?.paths, isEmpty);
  });

  group('לפי תצוגה', () {
    const channel = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_filedrop',
    );
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      PluginFileDropService.resetViewsForTesting();
    });

    test('התצוגה הראשית משתמשת בשירות הראשי', () {
      expect(
        PluginFileDropService.forView(null),
        PluginFileDropService.instance,
      );
      expect(PluginFileDropService.forView(0), PluginFileDropService.instance);
    });

    test('השירות הראשי אינו שולח מזהה תצוגה', () async {
      final main = PluginFileDropService();
      await main.acquire();
      await main.release();

      expect(calls.map((call) => call.arguments), [
        {'enabled': true},
        {'enabled': false},
      ]);
    }, skip: !Platform.isWindows);

    test('תצוגה אחרת מקבלת שירות משלה ששולח את המזהה שלה', () async {
      final other = PluginFileDropService.forView(7);
      expect(other, isNot(PluginFileDropService.instance));
      expect(PluginFileDropService.forView(7), same(other));

      await other.acquire();
      await other.release();

      expect(calls.map((call) => call.arguments), [
        {'enabled': true, 'viewId': 7},
        {'enabled': false, 'viewId': 7},
      ]);
      // האזור האחרון שוחרר — התצוגה הבאה במזהה הזה תקבל שירות חדש.
      expect(PluginFileDropService.forView(7), isNot(same(other)));
    }, skip: !Platform.isWindows);

    testWidgets('אזור בתצוגה אחרת נקשר לשירות שלה ומשחרר אותו', (
      tester,
    ) async {
      final zoneKey = GlobalKey<_ZoneState>();
      final secondary = _SecondaryTestView(tester.view);
      Widget host({required bool inSecondary}) => ViewCollection(
        views: [
          View(
            view: tester.view,
            child: inSecondary ? const SizedBox() : _Zone(key: zoneKey),
          ),
          View(
            view: secondary,
            child: inSecondary ? _Zone(key: zoneKey) : const SizedBox(),
          ),
        ],
      );

      await tester.pumpWidget(host(inSecondary: true), wrapWithView: false);
      expect(zoneKey.currentState!.dropService.viewId, 7);
      expect(calls.single.arguments, {'enabled': true, 'viewId': 7});

      // מעבר לתצוגה הראשית: משחרר את של 7 ונקשר לשירות הראשי.
      calls.clear();
      await tester.pumpWidget(host(inSecondary: false), wrapWithView: false);
      expect(
        zoneKey.currentState!.dropService,
        same(PluginFileDropService.instance),
      );
      expect(calls.map((call) => call.arguments), [
        {'enabled': false, 'viewId': 7},
        {'enabled': true},
      ]);

      calls.clear();
      await tester.pumpWidget(const SizedBox(), wrapWithView: true);
      expect(calls.single.arguments, {'enabled': false});
    }, skip: !Platform.isWindows);
  });
}

class _SecondaryTestView extends TestFlutterView {
  _SecondaryTestView(TestFlutterView base)
    : super(
        view: base,
        platformDispatcher: base.platformDispatcher,
        display: base.display,
      );

  @override
  int get viewId => 7;

  @override
  void render(ui.Scene scene, {Size? size}) {}
}

class _Zone extends StatefulWidget {
  const _Zone({super.key});

  @override
  State<_Zone> createState() => _ZoneState();
}

class _ZoneState extends State<_Zone> with PluginFileDropZoneBinding {
  @override
  void onFileDragChanged() {}

  @override
  void onFileDropped(PluginFileDrag drop) {}

  @override
  Widget build(BuildContext context) => const SizedBox();
}
