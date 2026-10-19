import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';

import '../helpers/memory_settings_cache.dart';

class _StubBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _StubBookmarkBloc(List<Bookmark> bookmarks)
    : super(BookmarkState(bookmarks: bookmarks));

  final List<int> removedIndexes = [];
  int clearAllCalls = 0;

  @override
  bool removeBookmark(int index) {
    removedIndexes.add(index);
    return true;
  }

  @override
  void clearBookmarks() => clearAllCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _StubTabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _StubNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading));

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  Future<_StubBookmarkBloc> pumpBookmarks(WidgetTester tester) async {
    final bookmarkBloc = _StubBookmarkBloc([
      Bookmark(
        ref: 'בראשית א',
        book: TextBook(title: 'בראשית', filePath: '/fake/בראשית.txt'),
        index: 1,
      ),
    ]);
    final tabsBloc = _StubTabsBloc();
    final navBloc = _StubNavigationBloc();

    addTearDown(() async {
      await bookmarkBloc.close();
      await tabsBloc.close();
      await navBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<NavigationBloc>.value(value: navBloc),
          ],
          child: const Scaffold(body: BookmarkView()),
        ),
      ),
    );
    await tester.pump();
    return bookmarkBloc;
  }

  // במסך מגע אין קליק ימני, ולכן מחיקה שזמינה רק בתפריט הקשר אינה נגישה כלל.
  testWidgets('שורת סימניה מציגה כפתור מחיקה גלוי', (tester) async {
    final bloc = await pumpBookmarks(tester);

    final deleteButton = find.byTooltip('מחק');
    expect(deleteButton, findsOneWidget);

    await tester.tap(deleteButton);
    await tester.pump();
    expect(bloc.removedIndexes, [0]);
  });

  testWidgets('מחיקת כל הסימניות דורשת אישור בדיאלוג', (tester) async {
    final bloc = await pumpBookmarks(tester);

    await tester.tap(find.text('מחק את כל הסימניות'));
    await tester.pumpAndSettle();

    expect(find.text('למחוק את כל הסימניות?'), findsOneWidget);
    expect(bloc.clearAllCalls, 0);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(bloc.clearAllCalls, 0);

    await tester.tap(find.text('מחק את כל הסימניות'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'מחק'));
    await tester.pumpAndSettle();
    expect(bloc.clearAllCalls, 1);
  });
}
