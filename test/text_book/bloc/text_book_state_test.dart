import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope;

void main() {
  group('TextBookLoaded equality', () {
    test('changes when spacing values change', () {
      final withSpacing = _loadedState(
        spacingValues: const {'0-1': '1'},
      );
      final withoutSpacing = _loadedState();

      expect(withSpacing, isNot(equals(withoutSpacing)));
    });

    test('changes when advanced search options change', () {
      final withOptions = _loadedState(
        searchOptions: const {
          'אמר_0': {'סיומות': true},
        },
      );
      final withoutOptions = _loadedState();

      expect(withOptions, isNot(equals(withoutOptions)));
    });

    test('changes when match policy changes', () {
      // ההשוואה חייבת לזהות את שינוי מדיניות ההתאמה, אחרת חלונית החיפוש
      // לא תריץ חיפוש מחדש כשהמשתמש עובר ל"באותה פסקה".
      final sameParagraph = _loadedState(
        matchPolicy: const SearchMatchPolicy(
          proximityScope: SearchScope.sameParagraph,
        ),
      );
      final wordDistance = _loadedState();

      expect(sameParagraph, isNot(equals(wordDistance)));
    });

    test('changes when search mode changes', () {
      final advanced = _loadedState(searchMode: SearchMode.advanced);
      final exact = _loadedState();

      expect(advanced, isNot(equals(exact)));
    });

    test('changes when typo tolerance option changes', () {
      final withTypoTolerance = _loadedState(
        searchOptions: const {
          'אמר_0': {'שגיאות כתיב': true},
        },
      );
      final withoutTypoTolerance = _loadedState(
        searchOptions: const {
          'אמר_0': {'שגיאות כתיב': false},
        },
      );

      expect(withTypoTolerance, isNot(equals(withoutTypoTolerance)));
    });

    test(
      'changes when content version changes even if content length stays same',
      () {
        final older = _loadedState(
          content: const ['שורה א'],
          contentVersion: 1,
        );
        final newer = _loadedState(
          content: const ['שורה ב'],
          contentVersion: 2,
        );

        expect(older, isNot(equals(newer)));
      },
    );
    test('changes when selected link types change', () {
      final withFilter = _loadedState(selectedLinkTypes: const {'REFERENCE'});
      final noFilter = _loadedState();

      expect(withFilter, isNot(equals(noFilter)));
    });

    test('changes when one link type is swapped for another of same size', () {
      final quotation = _loadedState(selectedLinkTypes: const {'QUOTATION'});
      final related = _loadedState(selectedLinkTypes: const {'RELATED'});

      expect(quotation, isNot(equals(related)));
    });

    test('changes when selected indices change', () {
      final single = _loadedState(selectedIndices: const {3});
      final multi = _loadedState(selectedIndices: const {3, 7});

      expect(single, isNot(equals(multi)));
    });

    test('selectedIndices defaults to empty', () {
      expect(_loadedState().selectedIndices, isEmpty);
    });

    test('changes when heCategories is enriched in background', () {
      final beforeEnrich = _loadedState();
      final afterEnrich = _loadedState(heCategories: 'תנ״ך, תורה');

      expect(beforeEnrich, isNot(equals(afterEnrich)));
    });

    test('changes when the Tanach nikud exemption changes', () {
      expect(
        _loadedState(nikudExemptByTanach: true),
        isNot(equals(_loadedState())),
      );
    });

    test('changes when the commentary nikud override changes', () {
      expect(
        _loadedState(commentaryRemoveNikudOverride: false),
        isNot(equals(_loadedState())),
      );
    });
  });

  group('commentaryRemoveNikud', () {
    test('hides nikud in commentaries of a Tanach book showing nikud', () {
      // הבאג: "הצג ניקוד בתנ״ך" הותיר ניקוד גם במפרשי התנ״ך.
      final state = _loadedState(
        removeNikud: false,
        nikudExemptByTanach: true,
      );

      expect(state.removeNikud, isFalse);
      expect(state.commentaryRemoveNikud, isTrue);
    });

    test('keeps the exemption when the toolbar re-shows nikud', () {
      final state = _loadedState(
        removeNikud: false,
        nikudExemptByTanach: true,
      );

      expect(state.copyWith(removeNikud: true).commentaryRemoveNikud, isTrue);
      expect(state.copyWith(removeNikud: false).commentaryRemoveNikud, isTrue);
    });

    test('commentary override does not change the main book', () {
      final state = _loadedState(
        removeNikud: false,
        nikudExemptByTanach: true,
      );

      final showingCommentaries = state.copyWith(
        commentaryRemoveNikudOverride: false,
      );

      expect(showingCommentaries.removeNikud, isFalse);
      expect(showingCommentaries.commentaryRemoveNikud, isFalse);
    });

    test('follows the tab when no exemption applies', () {
      final showing = _loadedState(removeNikud: false);
      final hiding = _loadedState(removeNikud: true);

      expect(showing.commentaryRemoveNikud, isFalse);
      expect(hiding.commentaryRemoveNikud, isTrue);
    });
  });
}

TextBookLoaded _loadedState({
  List<String> content = const ['שורה א'],
  int contentVersion = 0,
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  SearchMode searchMode = SearchMode.exact,
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  Set<int> selectedIndices = const {},
  Set<String> selectedLinkTypes = const {},
  String? heCategories,
  bool removeNikud = false,
  bool nikudExemptByTanach = false,
  bool? commentaryRemoveNikudOverride,
}) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה', heCategories: heCategories),
    showLeftPane: false,
    content: content,
    contentVersion: contentVersion,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    selectedLinkTypes: selectedLinkTypes,
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: removeNikud,
    nikudExemptByTanach: nikudExemptByTanach,
    commentaryRemoveNikudOverride: commentaryRemoveNikudOverride,
    visibleIndices: const [0],
    selectedIndices: selectedIndices,
    pinLeftPane: false,
    searchText: 'אמר רבי',
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: searchMode,
    matchPolicy: matchPolicy,
  );
}
