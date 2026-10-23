import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  /// stub חסר state — אין מה לשכפל.
  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// תקציב הזיכרון של ה-renderer מתחלק בין חלוניות אותו טאב: ארבע חלוניות PDF
/// עם התקציב המלא כל אחת הן תרחיש ה-OOM במחשבי 8GB.
void main() {
  group('חלוקת תקציב מטמון PDF', () {
    test('חלונית אחת מקבלת את התקציב המלא', () {
      expect(pdfImageCacheBytesForPanes(1), kPdfImageCacheBudgetBytes);
    });

    test('שתי חלוניות מתחלקות שווה בשווה', () {
      expect(pdfImageCacheBytesForPanes(2), kPdfImageCacheBudgetBytes ~/ 2);
    });

    test('התקציב הכולל נשמר בכל מספר חלוניות נתמך', () {
      for (var count = 1; count <= 8; count++) {
        final perPane = pdfImageCacheBytesForPanes(count);
        expect(perPane, greaterThan(0));
        expect(perPane * count, lessThanOrEqualTo(kPdfImageCacheBudgetBytes));
      }
    });

    test('מספר חלוניות חריג אינו מייצר ערך לא חוקי', () {
      for (final count in [0, -3, 1, 8, 64]) {
        final bytes = pdfImageCacheBytesForPanes(count);
        expect(bytes, greaterThan(0));
        expect(bytes, lessThanOrEqualTo(kPdfImageCacheBudgetBytes));
      }
    });

    test('התקציב יורד ככל שמתווספות חלוניות', () {
      expect(
        pdfImageCacheBytesForPanes(2),
        lessThan(pdfImageCacheBytesForPanes(1)),
      );
      expect(
        pdfImageCacheBytesForPanes(3),
        lessThanOrEqualTo(pdfImageCacheBytesForPanes(2)),
      );
    });
  });

  group('מספר החלוניות כמקור החלוקה', () {
    test('טאב שאינו מפוצל הוא חלונית אחת', () {
      expect(leafPanes(_LeafTab('בודד')).length, 1);
    });

    test('טאב מפוצל מדווח שתי חלוניות, וכל אחת מקבלת חצי תקציב', () {
      final split = CombinedTab(
        rightTab: _LeafTab('א'),
        leftTab: _LeafTab('ב'),
      );

      expect(leafPanes(split).length, 2);
      expect(
        pdfImageCacheBytesForPanes(leafPanes(split).length),
        kPdfImageCacheBudgetBytes ~/ 2,
      );
    });
  });
}
