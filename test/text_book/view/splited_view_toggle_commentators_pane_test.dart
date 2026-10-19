import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/text_book/view/splited_view/splited_view_screen.dart';
import 'package:otzaria/text_book/view/tabbed_commentary_panel.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/bloc/tour_state.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/widgets/navigation/panel_tab_header.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// טסט רגרסיה לטוגל חלונית המפרשים מקיצור המקלדת (issue #1161).
///
/// בעבר נחסם הקיצור במצב "מפרשים מתחת" (`showSplitView: false`) תחת ההנחה
/// השגויה שהחלונית אינה רלוונטית במצב זה. בפועל, החלונית מציגה את לשונית
/// "סינון מפרשים" (בחירת מפרשים), והקיצור מאפשר לפתוח ולסגור אותה בנוחות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookTitle = 'ספר בדיקה';

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> setSurfaceSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<TextBookTab> pumpSplitedView(
    WidgetTester tester, {
    required bool showSplitView,
  }) async {
    final book = TextBook(title: bookTitle);
    final textBookBloc = _TestTextBookBloc(
      _loadedState(book, showSplitView: showSplitView),
    );
    final personalNotesBloc = _TestPersonalNotesBloc(
      const PersonalNotesState.initial(),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final tab = TextBookTab(
      book: book,
      index: 0,
      blocOverride: textBookBloc,
    );
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final tourCubit = _TestTourCubit();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await personalNotesBloc.close();
      await settingsBloc.close();
      await tabsBloc.close();
      await tourCubit.close();
      tab.dispose();
    });

    await setSurfaceSize(tester, const Size(1200, 800));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<TourCubit>.value(value: tourCubit),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SplitedViewScreen(
              content: const ['פסקה א', 'פסקה ב'],
              openBookCallback: (_) {},
              searchTextController: TextEditingValue.empty,
              openLeftPaneTab: (_, {searchText}) {},
              onSelectedTextChanged: null,
              tab: tab,
              showSplitView: showSplitView,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    return tab;
  }

  group('קיצור מפרשים (toggleCommentatorsPaneNotifier) במצב "מפרשים מתחת"', () {
    testWidgets(
      'פתיחה: יריית ה-notifier פותחת את החלונית בלשונית סינון/בחירת מפרשים',
      (tester) async {
        final tab = await pumpSplitedView(tester, showSplitView: false);

        // במצב התחלתי החלונית סגורה וידית הפתיחה גלויה
        expect(find.byType(PanelOpenHandle), findsOneWidget);
        expect(find.byType(CommentatorsListView), findsNothing);

        // יריית ה-notifier (דימוי קיצור המקלדת)
        tab.toggleCommentatorsPaneNotifier.value++;
        await tester.pumpAndSettle();

        // החלונית נפתחת ומציגה את לשונית בחירת המפרשים (CommentatorsListView)
        expect(find.byType(PanelOpenHandle), findsNothing);
        expect(
          find.byType(CommentatorsListView),
          findsOneWidget,
          reason:
              'במצב מפרשים מתחת, הקיצור צריך לפתוח את חלונית בחירת המפרשים (issue #1161)',
        );
      },
    );

    testWidgets(
      'סגירה: יריית ה-notifier בפעם השנייה סוגרת את החלונית',
      (tester) async {
        final tab = await pumpSplitedView(tester, showSplitView: false);

        // ירייה 1: פתיחה
        tab.toggleCommentatorsPaneNotifier.value++;
        await tester.pumpAndSettle();
        expect(find.byType(CommentatorsListView), findsOneWidget);

        // ירייה 2: סגירה
        tab.toggleCommentatorsPaneNotifier.value++;
        await tester.pumpAndSettle();

        expect(find.byType(PanelOpenHandle), findsOneWidget);
      },
    );
  });

  group('קיצור מפרשים (toggleCommentatorsPaneNotifier) במצב "מפרשים בצד"', () {
    testWidgets('פתיחה וסגירה פועלות כסדרן', (tester) async {
      final tab = await pumpSplitedView(tester, showSplitView: true);

      // במצב split view עם התחלה ללא initialTabIndex:
      // ירייה 1: פתיחה
      tab.toggleCommentatorsPaneNotifier.value++;
      await tester.pumpAndSettle();
      expect(find.byType(TabbedCommentaryPanel), findsOneWidget);

      // ירייה 2: סגירה
      tab.toggleCommentatorsPaneNotifier.value++;
      await tester.pumpAndSettle();
      expect(find.byType(PanelOpenHandle), findsOneWidget);
    });
  });
}

TextBookLoaded _loadedState(TextBook book, {required bool showSplitView}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['פסקה א', 'פסקה ב'],
    fontSize: 18,
    showSplitView: showSplitView,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const <Link>[],
    visibleLinks: const <Link>[],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    currentTitle: 'סימן א',
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTourCubit extends Cubit<TourState> implements TourCubit {
  _TestTourCubit() : super(const TourState.inactive());

  @override
  Future<void> recordInteraction(TourInteraction interaction) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
