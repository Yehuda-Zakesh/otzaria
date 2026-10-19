import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder;

/// טאב חיפוש נבנה גם לפני שההעדפות אותחלו (טסטי ווידג'ט, אתחול מוקדם).
/// הקובץ הזה מריץ בכוונה בלי `Settings.init` — קריאת ההעדפה שם אסור שתקרוס.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('הקובץ אכן רץ בלי אתחול ההעדפות', () {
    expect(Settings.isInitialized, isFalse);
  });

  test('קריאת ההעדפות בלי אתחול מחזירה ברירות מחדל', () {
    expect(
      SearchDefaults.initialSortOrderForNewSearch(),
      ResultsOrder.catalogue,
    );
    expect(
      SearchDefaults.initialResultGroupingForNewSearch(),
      ResultGroupingMode.none,
    );
  });

  test('שמירת העדפה בלי אתחול אינה זורקת', () {
    expect(
      () => SearchDefaults.saveResultGroupingDefault(
        ResultGroupingMode.sameSection,
      ),
      returnsNormally,
    );
    expect(
      () => SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance),
      returnsNormally,
    );
  });

  test('withResultPreferences בלי אתחול מחזיר את ה-base כמו שהוא', () {
    const base = SearchConfiguration(searchMode: SearchMode.exact, distance: 2);

    expect(SearchDefaults.withResultPreferences(base), base);
  });

  test('בניית טאב חיפוש בלי אתחול ההעדפות אינה זורקת', () {
    final tab = SearchingTab('חיפוש', 'בראשית');
    addTearDown(tab.dispose);

    expect(tab.searchBloc.state.sortBy, ResultsOrder.catalogue);
    expect(tab.searchBloc.state.resultGrouping, ResultGroupingMode.none);
  });
}
