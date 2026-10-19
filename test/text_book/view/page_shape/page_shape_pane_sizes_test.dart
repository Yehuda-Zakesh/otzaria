import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_pane_sizes.dart';

void main() {
  group('pageShapeStoredFraction', () {
    test('יחס נשמר כמו שהוא', () {
      expect(pageShapeStoredFraction(0.25, 1000), 0.25);
    });

    test('פיקסלים מגרסה קודמת מומרים ביחס לחלון', () {
      expect(pageShapeStoredFraction(300, 1200), 0.25);
    });

    test('בלי גודל חלון אין המרה', () {
      expect(pageShapeStoredFraction(300, 0), isNull);
    });
  });

  group('pageShapeFraction', () {
    test('לא עולה על 1 גם כשהמינימום בפיקסלים גדול מהשטח', () {
      expect(pageShapeFraction(80, 60), 1.0);
    });
  });

  group('resolvePageShapeSideWidths', () {
    test('רוחב הטורים יחסי לרוחב הדף', () {
      final wide = resolvePageShapeSideWidths(
        freeWidth: 1000,
        leftFraction: 0.2,
        rightFraction: 0.1,
        hasLeft: true,
        hasRight: true,
      );
      expect(wide.left, closeTo(200, 0.001));
      expect(wide.right, closeTo(100, 0.001));
    });

    test('שני טורים רחבים מוקטנים יחד כדי להשאיר מקום לטקסט הראשי', () {
      final widths = resolvePageShapeSideWidths(
        freeWidth: 1000,
        leftFraction: 0.4,
        rightFraction: 0.4,
        hasLeft: true,
        hasRight: true,
      );
      expect(widths.left + widths.right, closeTo(700, 0.001));
      expect(widths.left, closeTo(widths.right, 0.001));
    });

    test('טור מוסתר לא נספר בחישוב המקום', () {
      final widths = resolvePageShapeSideWidths(
        freeWidth: 1000,
        leftFraction: 0.4,
        rightFraction: 0.4,
        hasLeft: true,
        hasRight: false,
      );
      expect(widths.left, closeTo(400, 0.001));
    });

    test('בדף צר כל טור נשאר ברוחב המזערי', () {
      final widths = resolvePageShapeSideWidths(
        freeWidth: 300,
        leftFraction: 0.17,
        rightFraction: 0.4,
        hasLeft: true,
        hasRight: true,
      );
      expect(widths.left, kPageShapeSideMinWidth);
      expect(widths.right, greaterThanOrEqualTo(kPageShapeSideMinWidth));
    });
  });
}
