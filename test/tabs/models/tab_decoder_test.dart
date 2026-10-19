import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// המפענח **היחיד** של טאב שמור.
///
/// ⚠️ קודם היו שלושה: `OpenedTab.fromJson` הכיר חמישה טיפוסים,
/// ו-`TabsRepository`, `Workspace.fromJson` ו-`decodeCombinedTab` עקפו אותו
/// עם טבלאות מקבילות משלהם. התוצאה שהמשתמש ראה: כרטיסיית מפרשים **כן**
/// נטענה מהדיסק ו**לא** הייתה ניתנת להעברה בין חלונות — כי כל מסלול עבר
/// במפענח אחר. שכפול של טבלת טיפוסים מתיישן בכיוונים שונים.
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  PdfBookTab pdfTab() => PdfBookTab(
    book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
    pageNumber: 7,
  );

  TextBookTab textTab() =>
      TextBookTab(book: TextBook(title: 'בראשית'), index: 3);

  group('OpenedTab.fromJson מכיר את כל תשעת הטיפוסים שנשמרים', () {
    test('CommentatorsTab', () {
      final source = CommentatorsTab(sourceTab: textTab());
      final restored = OpenedTab.fromJson(source.toJson());
      expect(restored, isA<CommentatorsTab>());
      expect((restored as CommentatorsTab).sourceTab.book.title, 'בראשית');
    });

    test('PdfCommentatorsTab', () {
      final source = PdfCommentatorsTab(sourceTab: pdfTab());
      final restored = OpenedTab.fromJson(source.toJson());
      expect(restored, isA<PdfCommentatorsTab>());
      expect((restored as PdfCommentatorsTab).sourceTab.book.title, 'ספר PDF');
    });

    test('כרטיסיית מפרשים בתוך טאב מפוצל', () {
      final split = CombinedTab(
        rightTab: textTab(),
        leftTab: CommentatorsTab(sourceTab: textTab()),
      );
      final restored = OpenedTab.fromJson(split.toJson());
      // ⚠️ שתי החלוניות, ולא רק השורדת: `decodeCombinedTab` היה בולע
      // חלונית שנכשלה, ולכן מפענח חסר היה מחזיר חצי טאב בשקט.
      expect(restored, isA<CombinedTab>());
      expect((restored as CombinedTab).leftTab, isA<CommentatorsTab>());
    });
  });

  group('PdfBookTab — מצב משתמש שנפל בין הכיסאות', () {
    test('בחירת המפרשים ומפלס התקריב שורדים round-trip', () {
      // ⚠️ `PdfCommentatorsTab` שומר את `activeCommentators` במפורש, כלומר
      // זהו מצב משתמש אמיתי. ב-`PdfBookTab` הוא לא נשמר בכלל, ולכן העברת
      // כרטיסיה לחלון אחר — וגם סגירת התוכנה — איפסה אותו.
      final tab = pdfTab()
        ..activeCommentators = {'רש"י', 'תוספות'}
        ..savedZoom = 1.75;

      final restored = OpenedTab.fromJson(tab.toJson()) as PdfBookTab;

      expect(restored.activeCommentators, {'רש"י', 'תוספות'});
      expect(restored.savedZoom, 1.75);
      expect(restored.pageNumber, 7);
    });

    test('כרטיסיה בלי בחירה אינה כותבת מפתחות ריקים', () {
      final json = pdfTab().toJson();
      expect(json.containsKey('activeCommentators'), isFalse);
      expect(json.containsKey('savedZoom'), isFalse);
    });
  });
}
