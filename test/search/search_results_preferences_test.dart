import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultGrouping, ResultsOrder, SearchScope;

import '../helpers/memory_settings_cache.dart';
import '../support/recording_search_engine.dart';
import '../support/search_engine_test_init.dart';

/// מיון התוצאות ומצב איחוד התוצאות הם בחירת תצוגה שהמשתמש עושה פעם אחת.
/// בלי שמירה, כל חיפוש חדש נפתח שוב ב"ללא איחוד" — והמשתמש חוזר ובוחר.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  const sortKey = 'key-search-results-sort-order';
  const groupingKey = 'key-search-results-grouping';

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('העדפות תצוגת התוצאות נשמרות', () {
    test('בלי העדפה שמורה מוחזרות ברירות המחדל', () {
      expect(
        SearchDefaults.initialSortOrderForNewSearch(),
        ResultsOrder.catalogue,
      );
      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.none,
      );
    });

    test('כל מצבי האיחוד נשמרים ונטענים', () {
      for (final mode in ResultGroupingMode.values) {
        SearchDefaults.saveResultGroupingDefault(mode);
        expect(
          SearchDefaults.initialResultGroupingForNewSearch(),
          mode,
          reason: mode.label,
        );
      }
    });

    test('כל סדרי המיון נשמרים ונטענים', () {
      for (final order in ResultsOrder.values) {
        SearchDefaults.saveSortOrderDefault(order);
        expect(
          SearchDefaults.initialSortOrderForNewSearch(),
          order,
          reason: order.name,
        );
      }
    });

    test('חזרה ל"ללא איחוד" נשמרת אף היא ואינה נופלת לערך הקודם', () {
      SearchDefaults.saveResultGroupingDefault(
        ResultGroupingMode.identicalText,
      );
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.none);

      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.none,
      );
    });

    test('המיון והאיחוד נשמרים במפתחות נפרדים ואינם דורסים זה את זה', () {
      SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.sameSection);

      expect(
        SearchDefaults.initialSortOrderForNewSearch(),
        ResultsOrder.relevance,
      );
      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.sameSection,
      );
    });

    test('ההעדפה נשמרת בשם ולא באינדקס', () {
      SearchDefaults.saveResultGroupingDefault(
        ResultGroupingMode.identicalText,
      );
      SearchDefaults.saveSortOrderDefault(ResultsOrder.generation);

      expect(Settings.getValue<String>(groupingKey), 'identicalText');
      expect(Settings.getValue<String>(sortKey), 'generation');
    });

    test('ערך שמור שאינו מוכר נופל לברירת המחדל', () async {
      await Settings.setValue<String>(groupingKey, 'byChapter');
      await Settings.setValue<String>(sortKey, 'byAuthor');

      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.none,
      );
      expect(
        SearchDefaults.initialSortOrderForNewSearch(),
        ResultsOrder.catalogue,
      );
    });

    test('ערך שמור ריק נופל לברירת המחדל', () async {
      await Settings.setValue<String>(groupingKey, '');
      await Settings.setValue<String>(sortKey, '');

      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.none,
      );
      expect(
        SearchDefaults.initialSortOrderForNewSearch(),
        ResultsOrder.catalogue,
      );
    });
  });

  group('withResultPreferences', () {
    test('בלי base — ברירות המחדל בתוספת ההעדפות השמורות', () {
      SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.sameSection);

      final config = SearchDefaults.withResultPreferences();

      expect(config.sortBy, ResultsOrder.relevance);
      expect(config.resultGrouping, ResultGroupingMode.sameSection);
    });

    test('שאר שדות ה-base נשמרים במלואם', () {
      SearchDefaults.saveResultGroupingDefault(
        ResultGroupingMode.identicalText,
      );

      const base = SearchConfiguration(
        searchMode: SearchMode.fuzzy,
        distance: 3,
        proximityScope: SearchScope.sameParagraph,
        currentFacets: ['/תנך'],
        searchScopeFacets: ['/תנך'],
        numResults: 250,
        wordMatchCount: 4,
      );

      final config = SearchDefaults.withResultPreferences(base);

      expect(config.resultGrouping, ResultGroupingMode.identicalText);
      expect(config.searchMode, SearchMode.fuzzy);
      expect(config.distance, 3);
      expect(config.proximityScope, SearchScope.sameParagraph);
      expect(config.currentFacets, ['/תנך']);
      expect(config.searchScopeFacets, ['/תנך']);
      expect(config.numResults, 250);
      expect(config.wordMatchCount, 4);
    });

    test('בלי העדפה שמורה ה-base אינו משתנה בכלל', () {
      const base = SearchConfiguration(
        searchMode: SearchMode.exact,
        distance: 2,
      );

      expect(SearchDefaults.withResultPreferences(base), base);
    });
  });

  group('SearchBloc שומר את בחירת המשתמש', () {
    SearchBloc buildBloc({SearchConfiguration? configuration}) {
      final bloc = SearchBloc(
        initialConfiguration:
            configuration ?? const SearchConfiguration(currentFacets: ['/']),
        repository: SearchRepository(
          engineProvider: () async => RecordingSearchEngine(),
        ),
      );
      addTearDown(bloc.close);
      return bloc;
    }

    test('בחירת מצב איחוד נשמרת להעדפות', () async {
      final bloc = buildBloc();

      bloc.add(UpdateResultGrouping(ResultGroupingMode.sameSection));
      await pumpEventQueue();

      expect(bloc.state.resultGrouping, ResultGroupingMode.sameSection);
      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.sameSection,
      );
    });

    test('בחירת מיון נשמרת להעדפות', () async {
      final bloc = buildBloc();

      bloc.add(UpdateSortOrder(ResultsOrder.relevance));
      await pumpEventQueue();

      expect(bloc.state.sortBy, ResultsOrder.relevance);
      expect(
        SearchDefaults.initialSortOrderForNewSearch(),
        ResultsOrder.relevance,
      );
    });

    test('בחירה אחרונה גוברת על קודמת', () async {
      final bloc = buildBloc();

      bloc.add(UpdateResultGrouping(ResultGroupingMode.identicalText));
      await pumpEventQueue();
      bloc.add(UpdateResultGrouping(ResultGroupingMode.none));
      await pumpEventQueue();

      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.none,
      );
    });

    // בטאב משוחזר ה-state כבר במצב שהמשתמש בוחר, וההעדפה עדיין מפגרת אחריו.
    test('בחירה שזהה למוצג נשמרת גם כשאין שינוי state', () async {
      final bloc = buildBloc(
        configuration: const SearchConfiguration(
          currentFacets: ['/'],
          resultGrouping: ResultGroupingMode.sameSection,
        ),
      );

      bloc.add(UpdateResultGrouping(ResultGroupingMode.sameSection));
      await pumpEventQueue();

      expect(
        SearchDefaults.initialResultGroupingForNewSearch(),
        ResultGroupingMode.sameSection,
      );
    });

    // אותו מלכוד במיון: אין שם early return היום, ואם יתווסף אחד — הבחירה
    // בטאב משוחזר חייבת להמשיך להישמר.
    test('בחירת מיון שזהה למוצג נשמרת אף היא', () async {
      final bloc = buildBloc(
        configuration: const SearchConfiguration(
          currentFacets: ['/'],
          sortBy: ResultsOrder.relevance,
        ),
      );

      bloc.add(UpdateSortOrder(ResultsOrder.relevance));
      await pumpEventQueue();

      expect(
        SearchDefaults.initialSortOrderForNewSearch(),
        ResultsOrder.relevance,
      );
    });
  });

  group('הסתרת עץ התוצאות נשמרת גלובלית', () {
    const treeKey = 'key-search-results-tree-open';

    test('בלי העדפה שמורה העץ פתוח', () {
      expect(SearchDefaults.initialResultsTreeOpenForNewSearch(), isTrue);
    });

    test('הסתרה נשמרת ונטענת', () {
      SearchDefaults.saveResultsTreeOpenDefault(false);

      expect(Settings.getValue<bool>(treeKey), isFalse);
      expect(SearchDefaults.initialResultsTreeOpenForNewSearch(), isFalse);
    });

    test('חזרה להצגה נשמרת אף היא', () {
      SearchDefaults.saveResultsTreeOpenDefault(false);
      SearchDefaults.saveResultsTreeOpenDefault(true);

      expect(SearchDefaults.initialResultsTreeOpenForNewSearch(), isTrue);
    });

    test('טאב חדש נפתח לפי ההעדפה השמורה', () {
      SearchDefaults.saveResultsTreeOpenDefault(false);

      final tab = SearchingTab('חיפוש', null);
      addTearDown(tab.dispose);

      expect(tab.isLeftPaneOpen.value, isFalse);
    });
  });

  group('אפשרויות החיפוש החכם נשמרות (issue #2511)', () {
    test('בלי העדפה שמורה שתיהן פעילות', () {
      expect(SearchDefaults.initialSemanticIncludeLexicalForNewSearch(), true);
      expect(SearchDefaults.initialSemanticGroupIdenticalForNewSearch(), true);
    });

    test('כיבוי והפעלה מחדש נשמרים, כל אפשרות בנפרד', () {
      SearchDefaults.saveSemanticIncludeLexicalDefault(false);
      expect(SearchDefaults.initialSemanticIncludeLexicalForNewSearch(), false);
      expect(SearchDefaults.initialSemanticGroupIdenticalForNewSearch(), true);

      SearchDefaults.saveSemanticGroupIdenticalDefault(false);
      SearchDefaults.saveSemanticIncludeLexicalDefault(true);
      expect(SearchDefaults.initialSemanticIncludeLexicalForNewSearch(), true);
      expect(SearchDefaults.initialSemanticGroupIdenticalForNewSearch(), false);
    });
  });

  group('טאב חיפוש חדש נפתח עם ההעדפה', () {
    test('טאב בלי configuration מקבל את המיון והאיחוד השמורים', () {
      SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.sameSection);

      final tab = SearchingTab('חיפוש', 'בראשית ברא');
      addTearDown(tab.dispose);

      expect(tab.searchBloc.state.sortBy, ResultsOrder.relevance);
      expect(
        tab.searchBloc.state.resultGrouping,
        ResultGroupingMode.sameSection,
      );
    });

    test('טאב בלי configuration ובלי העדפה שמורה — ברירות המחדל', () {
      final tab = SearchingTab('חיפוש', null);
      addTearDown(tab.dispose);

      expect(tab.searchBloc.state.sortBy, ResultsOrder.catalogue);
      expect(tab.searchBloc.state.resultGrouping, ResultGroupingMode.none);
    });

    test('configuration מפורשת גוברת על ההעדפה — שחזור אינו נחטף', () {
      SearchDefaults.saveResultGroupingDefault(
        ResultGroupingMode.identicalText,
      );

      final tab = SearchingTab(
        'חיפוש',
        null,
        initialConfiguration: const SearchConfiguration(
          resultGrouping: ResultGroupingMode.none,
          sortBy: ResultsOrder.generation,
        ),
      );
      addTearDown(tab.dispose);

      expect(tab.searchBloc.state.resultGrouping, ResultGroupingMode.none);
      expect(tab.searchBloc.state.sortBy, ResultsOrder.generation);
    });

    // ההיסטוריה שומרת את הקונפיגורציה כמפה ובונה ממנה את הטאב; זה מסלול
    // השחזור השלישי, והיחיד שמרכיב את ה-config בעצמו.
    test('פריט היסטוריה נושא את המיון והאיחוד שנשמרו איתו', () {
      const saved = SearchConfiguration(
        sortBy: ResultsOrder.relevance,
        resultGrouping: ResultGroupingMode.sameSection,
      );
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.none);
      SearchDefaults.saveSortOrderDefault(ResultsOrder.catalogue);

      final fromHistory = SearchConfiguration.fromMap(
        saved.toMap(),
      ).copyWith(currentFacets: ['/תנך'], searchScopeFacets: ['/תנך']);
      final tab = SearchingTab(
        'חיפוש',
        null,
        initialConfiguration: fromHistory,
      );
      addTearDown(tab.dispose);

      expect(tab.searchBloc.state.sortBy, ResultsOrder.relevance);
      expect(
        tab.searchBloc.state.resultGrouping,
        ResultGroupingMode.sameSection,
      );
      expect(tab.searchBloc.state.currentFacets, ['/תנך']);
    });

    test('שכפול טאב נושא את מצב המקור ולא את ההעדפה', () {
      final original = SearchingTab(
        'חיפוש',
        'בראשית',
        initialConfiguration: const SearchConfiguration(
          resultGrouping: ResultGroupingMode.identicalText,
        ),
      );
      addTearDown(original.dispose);
      SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.none);

      final clone = SearchingTab.clone(original);
      addTearDown(clone.dispose);

      expect(
        clone.searchBloc.state.resultGrouping,
        ResultGroupingMode.identicalText,
      );
    });
  });

  group(
    'ההעדפה מגיעה עד למנוע',
    () {
      test('החיפוש הראשון בטאב חדש נשלח למנוע מקובץ', () async {
        SearchDefaults.saveResultGroupingDefault(
          ResultGroupingMode.sameSection,
        );
        SearchDefaults.saveSortOrderDefault(ResultsOrder.relevance);
        final engine = RecordingSearchEngine();
        final bloc = SearchBloc(
          initialConfiguration: SearchDefaults.withResultPreferences(
            const SearchConfiguration(currentFacets: ['/']),
          ),
          repository: SearchRepository(engineProvider: () async => engine),
        );
        addTearDown(bloc.close);

        bloc.add(UpdateSearchQuery('בראשית ברא'));
        await bloc.stream.firstWhere((state) => !state.isLoading);

        expect(engine.lastRequest!.grouping, ResultGrouping.sameSection);
        expect(engine.lastRequest!.order, ResultsOrder.relevance);
      });

      test('"ללא איחוד" שמור אינו מקבץ במנוע', () async {
        SearchDefaults.saveResultGroupingDefault(ResultGroupingMode.none);
        final engine = RecordingSearchEngine();
        final bloc = SearchBloc(
          initialConfiguration: SearchDefaults.withResultPreferences(
            const SearchConfiguration(currentFacets: ['/']),
          ),
          repository: SearchRepository(engineProvider: () async => engine),
        );
        addTearDown(bloc.close);

        bloc.add(UpdateSearchQuery('בראשית ברא'));
        await bloc.stream.firstWhere((state) => !state.isLoading);

        expect(engine.lastRequest!.grouping, isNull);
      });
    },
    skip: engineReady ? null : searchEngineSkipReason,
  );
}
