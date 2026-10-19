import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// `OpenedTab.clone` הוא החוזה שמבדיל בין "שני ערכים ברשימה" לבין "שני
/// אובייקטים". כשהוא החזיר `this`, שכפול טאב ומעבר בין שולחנות עבודה יצרו
/// שתי כניסות שמצביעות על אותו מופע — ו-`dispose` של האחת סגר את ה-BLoC
/// והבקרים של השנייה. הבדיקות כאן נועלות את אי-התלות.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab makePdfTab({String title = 'ספר PDF'}) => PdfBookTab(
    book: PdfBook(title: title, path: '/nonexistent/x.pdf'),
    pageNumber: 3,
  );

  group('כל תת-מחלקה מחזירה עותק ולא alias', () {
    test('TextBookTab', () {
      final original = TextBookTab(book: TextBook(title: 'בראשית'), index: 4);
      addTearDown(original.dispose);
      final clone = original.clone();
      addTearDown(clone.dispose);

      expect(identical(clone, original), isFalse);
      expect(clone, isA<TextBookTab>());
      expect((clone as TextBookTab).index, 4);
    });

    test('PdfBookTab', () {
      final original = makePdfTab();
      addTearDown(original.dispose);
      final clone = original.clone();
      addTearDown(clone.dispose);

      expect(identical(clone, original), isFalse);
      expect(clone, isA<PdfBookTab>());
      expect((clone as PdfBookTab).pageNumber, 3);
    });

    test('ToolTab', () {
      final original = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      addTearDown(original.dispose);
      final clone = original.clone();
      addTearDown(clone.dispose);

      expect(identical(clone, original), isFalse);
      expect((clone as ToolTab).toolId, 'builtin.calendar');
    });

    test('CombinedTab — גם שתי החלוניות מועתקות', () {
      // הכותרת נגזרת מהחלוניות וה-setter זורק, ולכן ההשוואה היא על
      // splitRatio, ההצמדה וזהות החלוניות.
      final original = CombinedTab(
        rightTab: TextBookTab(book: TextBook(title: 'ימין'), index: 1),
        leftTab: TextBookTab(book: TextBook(title: 'שמאל'), index: 2),
        splitRatio: 0.3,
        isPinned: true,
      );
      addTearDown(original.dispose);

      final clone = original.clone() as CombinedTab;
      addTearDown(clone.dispose);

      expect(identical(clone, original), isFalse);
      expect(identical(clone.rightTab, original.rightTab), isFalse);
      expect(identical(clone.leftTab, original.leftTab), isFalse);
      expect(clone.splitRatio, 0.3);
      expect(clone.isPinned, isTrue);
      expect(clone.rightTab.title, 'ימין');
      expect(clone.leftTab.title, 'שמאל');
    });

    test('_RestoredCombinedTab — נגיש רק דרך decodeCombinedTab', () {
      // הטיפוס פרטי ונוצר אך ורק מפיצול מקונן; מגיעים אליו דרך JSON.
      final nested = {
        'type': 'CombinedTab',
        'splitRatio': 0.4,
        'isPinned': false,
        'rightTab': {
          'type': 'CombinedTab',
          'splitRatio': 0.5,
          'rightTab': _textTabJson('פנימי-ימין'),
          'leftTab': _textTabJson('פנימי-שמאל'),
        },
        'leftTab': _textTabJson('חיצוני-שמאל'),
      };

      final restored = decodeCombinedTab(nested);
      addTearDown(restored.dispose);

      final clone = restored.clone();
      addTearDown(clone.dispose);

      expect(identical(clone, restored), isFalse);
      expect(clone.runtimeType, restored.runtimeType);
    });
  });

  group('CommentatorsTab', () {
    test('השכפול מקבל sourceTab נפרד ושומר את הבחירה', () {
      final source = TextBookTab(book: TextBook(title: 'בראשית'), index: 9);
      final original = CommentatorsTab(sourceTab: source)
        ..selectedCommentators = ['רש"י', 'רמב"ן']
        ..isPinned = true;
      addTearDown(original.dispose);
      addTearDown(source.dispose);

      final clone = original.clone() as CommentatorsTab;
      addTearDown(clone.dispose);

      expect(identical(clone.sourceTab, original.sourceTab), isFalse);
      expect(clone.sourceTab, isA<TextBookTab>());
      expect(clone.sourceTab.book.title, 'בראשית');
      expect(clone.selectedCommentators, ['רש"י', 'רמב"ן']);
      expect(clone.isPinned, isTrue);

      // רשימת הבחירה מועתקת ואינה משותפת.
      clone.selectedCommentators!.add('אבן עזרא');
      expect(original.selectedCommentators, ['רש"י', 'רמב"ן']);
    });

    test('שחרור השכפול אינו סוגר את ה-bloc של המקור', () {
      final source = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
      final original = CommentatorsTab(sourceTab: source);
      addTearDown(original.dispose);
      addTearDown(source.dispose);

      final clone = original.clone() as CommentatorsTab;
      clone.dispose();

      expect(original.bloc.isClosed, isFalse);
      expect(source.bloc.isClosed, isFalse);
    });
  });

  group('PdfCommentatorsTab', () {
    test('השכפול מקבל sourceTab נפרד ושומר את בחירת המפרשים', () {
      // ארבעת השדות נקבעים אחרי הבנייה ולכן `OpenedTab.from` לא מעביר אותם;
      // בלי ההעתקה המפורשת הכרטיסייה המשוכפלת נפתחה בלי מפרשים.
      final source = makePdfTab()
        ..activeCommentators = {'רש"י', 'תוספות'}
        ..currentTextLineNumber = 12
        ..currentTextLineNumberEnd = 34;
      final original = PdfCommentatorsTab(sourceTab: source)..isPinned = true;
      addTearDown(original.dispose);
      addTearDown(source.dispose);

      final clone = original.clone() as PdfCommentatorsTab;
      addTearDown(clone.dispose);

      expect(identical(clone.sourceTab, original.sourceTab), isFalse);
      expect(clone.sourceTab, isA<PdfBookTab>());
      expect(clone.sourceTab.activeCommentators, {'רש"י', 'תוספות'});
      expect(clone.sourceTab.currentTextLineNumber, 12);
      expect(clone.sourceTab.currentTextLineNumberEnd, 34);
      expect(clone.isPinned, isTrue);

      // ה-Set מועתק ואינו משותף.
      clone.sourceTab.activeCommentators.add('רשב"ם');
      expect(original.sourceTab.activeCommentators, {'רש"י', 'תוספות'});
    });
  });

  group('ResolvingTab', () {
    test('clone מחזיר את טיפוס ה-fallback ואינו זורק', () {
      // בדיקת רגרסיה: הפיכת clone ל-throw הייתה מפילה סגירת טאב שנפתח
      // מהחיפוש — `_rememberClosedTab` קורא ל-`OpenedTab.from`.
      final fallback = TextBookTab(book: TextBook(title: 'בראשית'), index: 2);
      final original = ResolvingTab(
        fallbackTab: fallback,
        resolve: () async => fallback,
      );
      addTearDown(original.dispose);

      final clone = original.clone();
      addTearDown(clone.dispose);

      expect(clone, isA<TextBookTab>());
      expect(identical(clone, fallback), isFalse);
    });
  });
}

Map<String, dynamic> _textTabJson(String title) => {
  'type': 'TextBookTab',
  'title': title,
  'initalIndex': 0,
  'commentators': <String>[],
  'showLeftPane': false,
};
