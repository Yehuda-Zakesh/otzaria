import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_summary.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

/// חלונית הסינון מול סיכום של ספק חיצוני: התפר שבין
/// [ExternalSearchSummary.namedOtherBooks] לשורות הספרים שתחת דלי
/// "עוד מ<מקור>" בעץ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Library makeLibrary() {
    final tanach = Category(
      title: 'תנ"ך',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [],
      parent: null,
    );
    final library = Library(categories: [tanach]);
    tanach.parent = library;
    return library;
  }

  late _MockSearchBloc searchBloc;
  late _MockLibraryBloc libraryBloc;
  late _MockSettingsBloc settingsBloc;
  late StreamController<SearchState> searchStates;
  late SearchingTab tab;

  ExternalSearchSummary summaryWith({
    int otherBooks = 2,
    List<ExternalSearchBook> books = const [
      ExternalSearchBook(id: 42, title: 'שו"ת מהרש"ם', hits: 7),
      ExternalSearchBook(id: 43, title: 'דרשות הר"ן', hits: 2),
    ],
  }) => ExternalSearchSummary(
    sourceTitle: 'היברובוקס',
    totalBooks: 3,
    categoryBookCounts: const {'/תנ"ך': 1},
    otherBooks: otherBooks,
    namedOtherBooks: books,
  );

  void setUpBlocs({
    List<String> currentFacets = const ['/'],
    bool externalResultsFirst = false,
  }) {
    searchStates = StreamController<SearchState>.broadcast();
    searchBloc = _MockSearchBloc();
    whenListen(
      searchBloc,
      searchStates.stream,
      initialState: SearchState(
        searchQuery: 'ניגונים',
        facetCounts: const {'/': 4, '/תנ"ך': 4},
        configuration: SearchConfiguration(currentFacets: currentFacets),
      ),
    );

    libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: makeLibrary(),
        isLoading: false,
        currentCategory: null,
      ),
    );

    settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        externalResultsFirst: externalResultsFirst,
      ),
    );
  }

  setUp(() {
    tab = SearchingTab('חיפוש', null);
  });

  tearDown(() async {
    tab.dispose();
    await searchStates.close();
    await searchBloc.close();
    await libraryBloc.close();
    await settingsBloc.close();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SearchBloc>.value(value: searchBloc),
              BlocProvider<LibraryBloc>.value(value: libraryBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: SizedBox(
              width: 320,
              height: 600,
              child: SearchFacetFiltering(tab: tab),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder chevronOf(String title) => find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(NavTreeTile),
    ),
    matching: find.byType(IconButton),
  );

  testWidgets('הדלי נפתח לספרים ששמותיהם הגיעו מהספק', (tester) async {
    setUpBlocs();
    await pumpPanel(tester);
    tab.externalSearchSummary.value = summaryWith();
    await tester.pump();

    expect(find.text('עוד מהיברובוקס'), findsOneWidget);
    expect(find.text('שו"ת מהרש"ם'), findsNothing);

    await tester.tap(chevronOf('עוד מהיברובוקס'));
    await tester.pump();

    expect(find.text('שו"ת מהרש"ם'), findsOneWidget);
    expect(find.text('דרשות הר"ן'), findsOneWidget);
  });

  testWidgets('בלי שמות מהספק אין מה לפתוח', (tester) async {
    setUpBlocs();
    await pumpPanel(tester);
    tab.externalSearchSummary.value = summaryWith(books: const []);
    await tester.pump();

    expect(find.text('עוד מהיברובוקס'), findsOneWidget);
    expect(chevronOf('עוד מהיברובוקס'), findsNothing);
  });

  testWidgets('ספר נבחר בדלי משאיר את הדלי בעץ גם כשהתרוקן', (tester) async {
    // חיפוש חדש סיווג הכול, והבחירה הקודמת (ספר בדלי) עדיין פעילה: בלי
    // השורה הזו אין בעץ שום ייצוג לסינון הפעיל, ואין דרך לבטלו.
    setUpBlocs(currentFacets: const ['/עוד מהיברובוקס/#42']);
    await pumpPanel(tester);
    tab.externalSearchSummary.value = summaryWith(
      otherBooks: 0,
      books: const [],
    );
    await tester.pump();

    expect(find.text('עוד מהיברובוקס'), findsOneWidget);
  });

  testWidgets('דלי ריק בלי סינון פעיל אינו מוצג', (tester) async {
    setUpBlocs();
    await pumpPanel(tester);
    tab.externalSearchSummary.value = summaryWith(
      otherBooks: 0,
      books: const [],
    );
    await tester.pump();

    expect(find.text('עוד מהיברובוקס'), findsNothing);
  });

  testWidgets('ברירת המחדל (מאוחרות) — הדלי אחרי קטגוריות הספרייה', (
    tester,
  ) async {
    setUpBlocs();
    await pumpPanel(tester);
    tab.externalSearchSummary.value = summaryWith();
    await tester.pump();

    final bucketY = tester.getTopLeft(find.text('עוד מהיברובוקס')).dy;
    final libraryY = tester.getTopLeft(find.text('תנ"ך')).dy;
    expect(bucketY, greaterThan(libraryY));
  });

  testWidgets('"קודמות" — הדלי בראש העץ, לפני קטגוריות הספרייה', (
    tester,
  ) async {
    setUpBlocs(externalResultsFirst: true);
    await pumpPanel(tester);
    tab.externalSearchSummary.value = summaryWith();
    await tester.pump();

    final bucketY = tester.getTopLeft(find.text('עוד מהיברובוקס')).dy;
    final libraryY = tester.getTopLeft(find.text('תנ"ך')).dy;
    expect(bucketY, lessThan(libraryY));
  });
}
