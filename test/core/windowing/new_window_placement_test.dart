import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/new_window_placement.dart';

const PhysicalRect _work = (left: 0, top: 0, width: 1920, height: 1040);

SourceWindowPlacement _source(
  PhysicalRect normal, {
  bool maximized = false,
  int dpi = 96,
  PhysicalRect work = _work,
}) => SourceWindowPlacement(
  normal: normal,
  workArea: work,
  maximized: maximized,
  dpi: dpi,
);

void main() {
  group('cascadeNewWindowPlacement (#2989)', () {
    test('אותו גודל, מוזז במדרג', () {
      final result = cascadeNewWindowPlacement(
        _source((left: 100, top: 80, width: 900, height: 600)),
      );
      expect(result.bounds, (left: 130, top: 110, width: 900, height: 600));
      expect(result.maximized, isFalse);
    });

    test('המדרג מוכפל ב-DPI', () {
      final result = cascadeNewWindowPlacement(
        _source((left: 100, top: 80, width: 900, height: 600), dpi: 144),
      );
      expect(result.bounds.left, 145);
      expect(result.bounds.top, 125);
    });

    test('חריגה מאזור העבודה חוזרת לפינתו', () {
      final result = cascadeNewWindowPlacement(
        _source((left: 1000, top: 400, width: 900, height: 600)),
      );
      expect(result.bounds, (left: 0, top: 0, width: 900, height: 600));
    });

    test('בצג משני — חוזר לפינת אזור העבודה שלו', () {
      const work = (left: 1920, top: 0, width: 1280, height: 984);
      final result = cascadeNewWindowPlacement(
        _source((left: 2500, top: 500, width: 800, height: 600), work: work),
      );
      expect(result.bounds, (left: 1920, top: 0, width: 800, height: 600));
    });

    test('מסגרת שחורגת שמאלה/למעלה מוצמדת לאזור העבודה', () {
      final result = cascadeNewWindowPlacement(
        _source((left: -200, top: -100, width: 900, height: 600)),
      );
      expect(result.bounds, (left: 0, top: 0, width: 900, height: 600));
    });

    test('חלון גדול מאזור העבודה מוקטן אליו', () {
      final result = cascadeNewWindowPlacement(
        _source((left: -8, top: -8, width: 1936, height: 1056)),
      );
      expect(result.bounds, (left: 0, top: 0, width: 1920, height: 1040));
    });

    test('מקור ממוקסם → ממוקסם, והמסגרת הרגילה מדורגת', () {
      final result = cascadeNewWindowPlacement(
        _source(
          (left: 200, top: 150, width: 1000, height: 700),
          maximized: true,
        ),
      );
      expect(result.maximized, isTrue);
      expect(result.bounds, (left: 230, top: 180, width: 1000, height: 700));
    });

    test('מסך מלא → ממוקסם', () {
      final result = cascadeNewWindowPlacement(
        _source((left: 0, top: 0, width: 1920, height: 1080)),
        fullScreen: true,
      );
      expect(result.maximized, isTrue);
      expect(result.bounds, (left: 0, top: 0, width: 1920, height: 1040));
    });
  });

  group('SourceWindowPlacement.fromMap', () {
    test('מפענח תשובה מלאה', () {
      final placement = SourceWindowPlacement.fromMap({
        'left': 1,
        'top': 2,
        'width': 3,
        'height': 4,
        'workLeft': 5,
        'workTop': 6,
        'workWidth': 7,
        'workHeight': 8,
        'dpi': 120,
        'maximized': true,
      })!;
      expect(placement.normal, (left: 1, top: 2, width: 3, height: 4));
      expect(placement.workArea, (left: 5, top: 6, width: 7, height: 8));
      expect(placement.dpi, 120);
      expect(placement.maximized, isTrue);
    });

    test('תשובה חסרה או פגומה → null', () {
      expect(SourceWindowPlacement.fromMap(null), isNull);
      expect(SourceWindowPlacement.fromMap({'left': 1}), isNull);
      expect(
        SourceWindowPlacement.fromMap({
          'left': 0,
          'top': 0,
          'width': 0,
          'height': 10,
          'workLeft': 0,
          'workTop': 0,
          'workWidth': 10,
          'workHeight': 10,
        }),
        isNull,
      );
    });
  });

  group('openWindow מעביר את המיקום ל-runner', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late List<MethodCall> calls;
    Map<String, Object?>? placement;

    setUp(() {
      calls = [];
      placement = {
        'left': 100,
        'top': 80,
        'width': 900,
        'height': 600,
        'workLeft': 0,
        'workTop': 0,
        'workWidth': 1920,
        'workHeight': 1040,
        'dpi': 96,
        'maximized': true,
      };
      MultiWindowService.debugSupportedOverride = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
            calls.add(call);
            if (call.method == 'windowPlacement') return placement;
            if (call.method == 'openWindow') return true;
            return null;
          });
    });

    tearDown(() {
      MultiWindowService.debugSupportedOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MultiWindowService.channel, null);
    });

    Map<Object?, Object?> openArgs() =>
        calls.singleWhere((c) => c.method == 'openWindow').arguments as Map;

    test('חלון חדש יורש גודל ומיקסום ומדורג', () async {
      expect(await const MultiWindowService().openWindow(), isTrue);
      final args = openArgs();
      expect(args['bounds'], {
        'left': 130,
        'top': 110,
        'width': 900,
        'height': 600,
      });
      expect(args['maximized'], isTrue);
    });

    test('גרירה לנקודה אינה משתמשת במיקום המקור', () async {
      await const MultiWindowService().openWindow(origin: (x: 500, y: 300));
      expect(calls.any((c) => c.method == 'windowPlacement'), isFalse);
      final args = openArgs();
      expect(args['originX'], 500);
      expect(args.containsKey('bounds'), isFalse);
      expect(args.containsKey('maximized'), isFalse);
    });

    test('הצמדה/שחזור עם מסגרת — המסגרת נשמרת כלשונה', () async {
      const bounds = (left: 10, top: 20, width: 800, height: 600);
      await const MultiWindowService().openWindow(bounds: bounds);
      expect(calls.any((c) => c.method == 'windowPlacement'), isFalse);
      expect(openArgs()['bounds'], {
        'left': 10,
        'top': 20,
        'width': 800,
        'height': 600,
      });
    });

    test('שחזור בלי מסגרת שמורה אינו יורש', () async {
      await const MultiWindowService().openWindow(inheritPlacement: false);
      expect(calls.any((c) => c.method == 'windowPlacement'), isFalse);
      expect(openArgs().containsKey('bounds'), isFalse);
    });

    test('runner בלי windowPlacement → ההתנהגות הקודמת', () async {
      placement = null;
      await const MultiWindowService().openWindow();
      final args = openArgs();
      expect(args.containsKey('bounds'), isFalse);
      expect(args.containsKey('maximized'), isFalse);
    });
  });
}
