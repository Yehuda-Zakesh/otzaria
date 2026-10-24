import 'package:flutter_test/flutter_test.dart';
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
}
