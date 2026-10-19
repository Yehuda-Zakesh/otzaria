import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// `copyWith(rawActivePane: null)` לא ידע להבחין בין "אל תיגע" לבין "נקה",
/// כי `?? this.rawActivePane` קרא כל `null` כ"אל תיגע". התוצאה: מעבר לטאב
/// שבו אין חלונית מתאימה שימר את החלונית הפעילה של טאב אחר.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab pdf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/nonexistent/$title.pdf'),
    pageNumber: 1,
  );

  test('unchanged — החלונית הפעילה נשמרת', () {
    final second = pdf('ב');
    final split = CombinedTab(rightTab: pdf('א'), leftTab: second);
    final state = TabsState(
      tabs: [split],
      currentTabIndex: 0,
      rawActivePane: second,
    );

    final next = state.copyWith(forceUpdate: true);

    expect(next.rawActivePane, same(second));
    expect(next.activePane, same(second));
  });

  test('clear — נופל ל-panes.first ולא משמר חלונית של טאב אחר', () {
    // זה בדיוק המקרה של `_matchingPaneIn` שמחזיר null: הטאב עצמו הוא
    // ההתאמה, ואסור להשאיר חלונית פעילה שאינה בטאב המוצג.
    final otherPane = pdf('טאב אחר');
    final first = pdf('א');
    final currentSplit = CombinedTab(rightTab: first, leftTab: pdf('ב'));
    final state = TabsState(
      tabs: [
        currentSplit,
        CombinedTab(rightTab: otherPane, leftTab: pdf('ד')),
      ],
      currentTabIndex: 0,
      rawActivePane: otherPane,
    );

    final next = state.copyWith(activePane: const ActivePaneUpdate.clear());

    expect(next.rawActivePane, isNull);
    expect(next.activePane, same(first));
  });

  test('set — קובע את החלונית שהועברה', () {
    final first = pdf('א');
    final second = pdf('ב');
    final split = CombinedTab(rightTab: first, leftTab: second);
    final state = TabsState(tabs: [split], currentTabIndex: 0);

    expect(state.activePane, same(first));

    final next = state.copyWith(activePane: ActivePaneUpdate.set(second));

    expect(next.rawActivePane, same(second));
    expect(next.activePane, same(second));
    expect(next.lastReadingPane, same(second));
  });

  test('clear בטאב שכולו כלי — הקשר הקריאה הקודם נשמר', () {
    final book = pdf('ספר');
    final tool = ToolTab(toolId: 'builtin.gematria', title: 'גימטריה');
    // `lastReadingPane` נצבר רק דרך copyWith — הקונסטרוקטור מותיר אותו null.
    var state = const TabsState(
      tabs: [],
      currentTabIndex: 0,
    ).copyWith(tabs: [book, tool], currentTabIndex: 0);
    expect(state.readingPane, same(book));
    expect(state.lastReadingPane, same(book));

    state = state.copyWith(
      currentTabIndex: 1,
      activePane: const ActivePaneUpdate.clear(),
    );

    expect(state.activePane, same(tool));
    // הכלי אינו מיקום קריאה, ולכן ההקשר הקודם — שעדיין פתוח — נשמר.
    expect(state.readingPane, same(book));
  });
}
