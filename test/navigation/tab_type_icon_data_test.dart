import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../helpers/memory_settings_cache.dart';

/// [tabTypeIconData] הוא הגליף שמצויר במוק הגרירה של כרטיסיה שאין מה
/// לצלם בה, ולכן קריסה של המיפוי — כל הכרטיסיות מקבלות אותו אייקון —
/// אינה נראית בשום מקום אחר.
///
/// ⚠️ מה שהבדיקה הזו **אינה** מכסה: שהגליף עצמו מרונדר. `flutter_test`
/// אינו טוען גופני אייקונים, ולכן "ריבוע ריק במקום אייקון" נבדק רק
/// ידנית באפליקציה.
void main() {
  // `PdfBookTab` קורא ל-`Settings.getValue` בבנייה.
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  PdfBookTab pdfTab() => PdfBookTab(
    book: PdfBook(title: 'ספר', path: 'a.pdf'),
    pageNumber: 1,
  );

  TextBookTab textTab([String title = 'בראשית']) =>
      TextBookTab(book: TextBook(title: title, categoryId: 1), index: 0);

  test('כל סוג כרטיסיה מקבל את האייקון שלו', () {
    expect(tabTypeIconData(pdfTab()), FluentIcons.document_pdf_16_regular);
    expect(
      tabTypeIconData(SearchingTab('חיפוש', null)),
      FluentIcons.search_24_regular,
    );
    expect(
      tabTypeIconData(
        CombinedTab(rightTab: textTab(), leftTab: textTab('שמות')),
      ),
      FluentIcons.split_horizontal_24_regular,
    );
    expect(
      tabTypeIconData(ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה')),
      FluentIcons.toolbox_24_regular,
    );
    // ⚠️ כרטיסיית טקסט היא היחידה ש-`buildTabTypeIcon` מחזיר לה `null`,
    // וכאן היא **חייבת** לקבל אייקון: מוק בלי אייקון הוא מלבן ריק עם
    // כותרת תלויה באוויר.
    expect(tabTypeIconData(textTab()), FluentIcons.document_24_regular);
  });

  test('סוגי כרטיסיה שונים אינם מקבלים אותו אייקון', () {
    final icons = <OpenedTab>[
      pdfTab(),
      textTab(),
      SearchingTab('חיפוש', null),
      ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה'),
    ].map(tabTypeIconData).toSet();

    expect(icons, hasLength(4));
  });
}
