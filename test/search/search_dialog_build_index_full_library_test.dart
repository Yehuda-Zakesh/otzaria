import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/view/search_dialog.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUpAll(() => registerFallbackValue(CancelIndexing()));

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // העץ של LibraryBloc מסונן מהסתרות; אינדוקס עליו בנה סדר קטלוגי אחר
  // מזה של העלייה, ומזהי המסמכים החדשים התנגשו בקיימים.
  testWidgets('"בנה אינדקס" מאנדקס את העץ המלא ולא את העץ המסונן', (
    tester,
  ) async {
    final fullLibrary = Library(categories: [])
      ..books.addAll([
        TextBook(id: 1, title: 'גלוי'),
        TextBook(id: 2, title: 'מוסתר'),
      ]);
    final visibleLibrary = Library(categories: [])
      ..books.add(TextBook(id: 1, title: 'גלוי'));
    final previousLibrary =
        DataRepository.instance.cachedLibraryFutureForTesting;
    DataRepository.instance.library = Future.value(fullLibrary);
    final provider = TantivyDataProvider.instance;
    final previousInitialized = provider.isInitialized.value;
    final previousPaths = {...provider.indexedFilePaths};
    provider.indexedFilePaths.clear();
    provider.isInitialized.value = true;

    final historyBloc = _MockHistoryBloc();
    final indexingBloc = _MockIndexingBloc();
    final navigationBloc = _MockNavigationBloc();
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: visibleLibrary),
    );
    addTearDown(() async {
      provider.isInitialized.value = previousInitialized;
      provider.indexedFilePaths.addAll(previousPaths);
      if (previousLibrary != null) {
        DataRepository.instance.library = previousLibrary;
      } else {
        DataRepository.instance.invalidateLibraryCache();
      }
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
      await libraryBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
          ],
          child: const Scaffold(body: SearchDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('בנה אינדקס'));
    await tester.pumpAndSettle();

    final added = verify(() => indexingBloc.add(captureAny())).captured;
    final start = added.whereType<StartIndexing>().single;
    expect(start.library, same(fullLibrary));
  }, skip: !engineReady);
}
