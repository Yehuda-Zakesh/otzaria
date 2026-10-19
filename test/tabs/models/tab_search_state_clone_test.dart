import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../../test_helpers/memory_cache_provider.dart';

/// שכפול טאב (`OpenedTab.from`) משמש לשחזור טאב שנסגר, לשכפול ולמעבר בין
/// שולחנות עבודה. בלי קונפיגורציית החיפוש, החיפוש שבספר המשוחזר חוזר למסלול
/// המחרוזת הרצופה ומציג "אין תוצאות" על תוצאה שהחיפוש הגלובלי מצא.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  const policy = SearchMatchPolicy(
    proximityScope: SearchScope.sameParagraph,
    wordMatchMode: WordMatchMode.atLeast,
    wordMatchCount: 3,
  );

  test('שכפול טאב טקסט שומר את כל קונפיגורציית החיפוש', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 389,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, 'תדע זרעך');
    expect(clone.searchMode, SearchMode.advanced);
    expect(clone.searchDistance, 3);
    expect(clone.matchPolicy, policy);
    expect(clone.searchOptions, original.searchOptions);
    expect(clone.alternativeWords, original.alternativeWords);
    expect(clone.spacingValues, original.spacingValues);
  });

  test('שכפול טאב PDF שומר את כל קונפיגורציית החיפוש', () {
    final original = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 5,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as PdfBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, 'תדע זרעך');
    expect(clone.searchMode, SearchMode.advanced);
    expect(clone.searchDistance, 3);
    expect(clone.matchPolicy, policy);
    expect(clone.searchOptions, original.searchOptions);
    expect(clone.alternativeWords, original.alternativeWords);
    expect(clone.spacingValues, original.spacingValues);
  });

  test('תצורה נכנסת לטאב PDF בלי חלונית מחוברת נכתבת גם לשדה החיפוש', () {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 1,
      searchText: 'תדע',
    );
    addTearDown(tab.dispose);

    tab.applyIncomingSearchConfiguration(
      ReadingTabSearchState(
        searchText: 'תדע זרעך',
        searchOptions: const {
          'תדע_0': {'ראשי תיבות': true},
        },
        searchMode: SearchMode.advanced,
        searchDistance: 3,
        matchPolicy: policy,
      ),
    );

    expect(tab.searchText, 'תדע זרעך');
    expect(tab.searchController.text, 'תדע זרעך');
    expect(tab.searchMode, SearchMode.advanced);
    expect(tab.searchDistance, 3);
    expect(tab.matchPolicy, policy);
    expect(tab.searchOptions, {
      'תדע_0': {'ראשי תיבות': true},
    });
    expect(tab.incomingSearchConfiguration.value, isNotNull);
  });

  test('חלונית מחוברת שקלטה את התצורה מונעת כתיבה לשדה החיפוש', () {
    // כתיבה לשדה החיפוש הייתה מפעילה את ה-listener של החלונית עם התצורה
    // הישנה, ומריצה את השאילתה החדשה במסלול הפשוט.
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 1,
      searchText: 'תדע',
    );
    addTearDown(tab.dispose);

    void consume() {
      if (tab.incomingSearchConfiguration.value == null) return;
      tab.incomingSearchConfiguration.value = null;
    }

    tab.incomingSearchConfiguration.addListener(consume);
    addTearDown(() => tab.incomingSearchConfiguration.removeListener(consume));

    tab.applyIncomingSearchConfiguration(
      const ReadingTabSearchState(searchText: 'תדע זרעך', searchDistance: 3),
    );

    expect(tab.searchDistance, 3);
    expect(tab.searchController.text, 'תדע');
  });

  test('JSON round-trip של טאב טקסט שומר את כל קונפיגורציית החיפוש', () {
    // שמירת שולחן עבודה ויציאה מהאפליקציה: בלי השימור, הספר נפתח מחדש
    // כחיפוש מחרוזת רצופה והחלונית הציגה "אין תוצאות".
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 389,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final restored = TextBookTab.fromJson(original.toJson());
    addTearDown(restored.dispose);

    expect(restored.searchText, 'תדע זרעך');
    expect(restored.searchMode, SearchMode.advanced);
    expect(restored.searchDistance, 3);
    expect(restored.matchPolicy, policy);
    expect(restored.searchOptions, original.searchOptions);
    expect(restored.alternativeWords, original.alternativeWords);
    expect(restored.spacingValues, original.spacingValues);
  });

  test('JSON round-trip של טאב PDF שומר את כל קונפיגורציית החיפוש', () {
    final original = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/nonexistent/test.pdf'),
      pageNumber: 5,
      searchText: 'תדע זרעך',
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
      alternativeWords: const {
        0: ['ידע'],
      },
      spacingValues: const {'0-1': '2'},
      searchMode: SearchMode.advanced,
      searchDistance: 3,
      matchPolicy: policy,
    );
    addTearDown(original.dispose);

    final restored = PdfBookTab.fromJson(original.toJson());
    addTearDown(restored.dispose);

    expect(restored.searchText, 'תדע זרעך');
    expect(restored.searchMode, SearchMode.advanced);
    expect(restored.searchDistance, 3);
    expect(restored.matchPolicy, policy);
    expect(restored.searchOptions, original.searchOptions);
    expect(restored.alternativeWords, original.alternativeWords);
    expect(restored.spacingValues, original.spacingValues);
  });

  test('טאב בלי חיפוש נשמר בלי שדות חיפוש, ונטען כברירת מחדל', () {
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
    );
    addTearDown(original.dispose);

    final json = original.toJson();
    expect(json.containsKey('searchText'), isFalse);
    expect(json.containsKey('searchMode'), isFalse);

    final restored = TextBookTab.fromJson(json);
    addTearDown(restored.dispose);
    expect(restored.searchText, isEmpty);
    expect(restored.searchMode, SearchMode.exact);
    expect(restored.matchPolicy, SearchMatchPolicy.standard);
  });

  test('שמירה ישנה (בלי שדות חיפוש) נטענת בברירות המחדל', () {
    // תאימות לאחור: קבצי טאבים ושולחנות עבודה קיימים אינם מכילים את השדות.
    final restored = TextBookTab.fromJson({
      'title': 'בראשית',
      'initalIndex': 5,
      'commentators': <String>[],
      'showLeftPane': false,
      'searchMode': 'no-such-mode',
      'searchMatchPolicy': 'not-a-map',
    });
    addTearDown(restored.dispose);

    expect(restored.searchText, isEmpty);
    expect(restored.searchMode, SearchMode.exact);
    expect(restored.matchPolicy, SearchMatchPolicy.standard);
  });

  test('שכפול טאב טקסט מעדיף את מצב החיפוש המעודכן מה-BLoC', () {
    // המשתמש שינה את החיפוש בתוך הספר (חיפוש מתקדם מהחלונית): שדות הטאב
    // נשארים על הערכים שאיתם נפתח, וה-state הוא המצב האמיתי.
    final bloc = _LoadedTextBookBloc(
      _loadedState(
        searchText: 'תדע זרעך',
        searchMode: SearchMode.advanced,
        searchDistance: 3,
        matchPolicy: policy,
      ),
    );
    final original = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      searchText: 'ישן',
      blocOverride: bloc,
    );
    addTearDown(original.dispose);

    final clone = OpenedTab.from(original) as TextBookTab;
    addTearDown(clone.dispose);

    expect(clone.searchText, 'תדע זרעך');
    expect(clone.searchMode, SearchMode.advanced);
    expect(clone.searchDistance, 3);
    expect(clone.matchPolicy, policy);
  });
}

class _LoadedTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _LoadedTextBookBloc(super.initialState) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState({
  required String searchText,
  required SearchMode searchMode,
  required int searchDistance,
  required SearchMatchPolicy matchPolicy,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'בראשית'),
    showLeftPane: true,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: searchText,
    searchMode: searchMode,
    searchDistance: searchDistance,
    matchPolicy: matchPolicy,
  );
}
