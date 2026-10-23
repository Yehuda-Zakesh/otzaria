import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';

void main() {
  group('pdfSpreadSnapshotPixelRatio', () {
    test('חלון גדול מוגבל ל-1.6MP', () {
      final ratio = pdfSpreadSnapshotPixelRatio(
        viewSize: const Size(1600, 1000),
        devicePixelRatio: 2,
      );
      expect(ratio, 1.0);
    });

    test('חלון 4K אינו עוקף את תקרת הפיקסלים', () {
      const viewSize = Size(3840, 2160);
      final ratio = pdfSpreadSnapshotPixelRatio(
        viewSize: viewSize,
        devicePixelRatio: 1,
      );
      expect(
        viewSize.width * viewSize.height * ratio * ratio,
        closeTo(1600000, 0.001),
      );
    });

    test('תקרת הפיקסלים נשמרת גם בחלון רחב במיוחד', () {
      const viewSize = Size(7680, 2160);
      final ratio = pdfSpreadSnapshotPixelRatio(
        viewSize: viewSize,
        devicePixelRatio: 2,
      );
      expect(
        viewSize.width * viewSize.height * ratio * ratio,
        closeTo(1600000, 0.001),
      );
    });

    test('חלון קטן במסך צפוף — עד 1.35', () {
      expect(
        pdfSpreadSnapshotPixelRatio(
          viewSize: const Size(400, 300),
          devicePixelRatio: 3,
        ),
        1.35,
      );
    });
  });

  group('pdfSpreadPageRenderScale', () {
    test('לעולם לא מעל 1.5 (התקרה הקודמת)', () {
      expect(pdfSpreadPageRenderScale(zoom: 4, snapshotPixelRatio: 1.35), 1.5);
    });

    test('עמוד שלם בחלון — קנה מידה לפי המוצג, בחזקת 2', () {
      expect(pdfSpreadPageRenderScale(zoom: 0.6, snapshotPixelRatio: 1), 1.0);
      expect(pdfSpreadPageRenderScale(zoom: 0.4, snapshotPixelRatio: 1), 0.5);
    });

    test('צעדי זום קטנים בתוך מדרגה אינם דורשים רינדור מחדש', () {
      expect(
        pdfSpreadPageRenderScale(zoom: 0.55, snapshotPixelRatio: 1),
        pdfSpreadPageRenderScale(zoom: 0.95, snapshotPixelRatio: 1),
      );
    });

    test('ערך לא תקין — התקרה', () {
      expect(pdfSpreadPageRenderScale(zoom: 0, snapshotPixelRatio: 1), 1.5);
    });
  });
}
