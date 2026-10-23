import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  final ready = await tryInitSearchEngine();

  testWidgets('הזרם הנייטיבי מוצג דרך SearchBloc לפני השלמת החיפוש', (
    tester,
  ) async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final directory = Directory.systemTemp.createTempSync('search_streaming_');
    late SearchEngine engine;
    await tester.runAsync(() async {
      DataRepository.instance.library = Future.value(Library(categories: []));
      engine = await SearchEngine.newInstance(path: directory.path);
      await engine.addTextBook(
        title: 'ספר בדיקת זרם',
        topics: '/בדיקות',
        filePath: '/streaming.txt',
        text: List.generate(120, (i) => 'שלום עולם שורה $i').join('\n'),
        textStorage: TextStorage.inIndex,
      );
      await engine.commit();
    });
    final operations = _PausedRustOperations(engine);
    final bloc = (await tester.runAsync(
      () async => SearchBloc(
        repository: SearchRepository(engineProvider: () async => operations),
      ),
    ))!;
    final settings = SettingsBloc(repository: SettingsRepository());
    final tab = SearchingTab('חיפוש', '', searchBloc: bloc);
    addTearDown(() async {
      if (!operations.resume.isCompleted) operations.resume.complete();
      await bloc.close();
      await settings.close();
      tab.dispose();
      engine.dispose();
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: bloc),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: Scaffold(body: TantivySearchResults(tab: tab)),
        ),
      ),
    );
    await tester.runAsync(() async {
      final oldComplete = bloc.stream.firstWhere((s) => !s.isLoading);
      bloc.add(UpdateSearchQuery('עולם'));
      await oldComplete.timeout(const Duration(seconds: 10));
    });
    expect(bloc.state.results, isNotEmpty);
    operations.pauseNext = true;
    await tester.runAsync(() async {
      final started = bloc.stream.firstWhere((s) => s.isLoading);
      final firstChunk = bloc.stream.firstWhere((s) => s.results.isNotEmpty);
      bloc.add(UpdateSearchQuery('שלום'));
      final initial = await started.timeout(const Duration(seconds: 10));
      expect(initial.results, isEmpty);
      expect(initial.totalResults, 0);
      await firstChunk.timeout(const Duration(seconds: 10));
    });
    await tester.pump();
    await tester.pump();
    expect(bloc.state.results, hasLength(50));
    expect(bloc.state.totalResults, 120);
    expect(bloc.state.isLoading, isTrue);
    expect(find.text('ספר בדיקת זרם'), findsWidgets);

    await tester.runAsync(() async {
      final complete = bloc.stream.firstWhere((s) => !s.isLoading);
      operations.resume.complete();
      await complete.timeout(const Duration(seconds: 10));
    });
    await tester.pump();
    expect(bloc.state.results, hasLength(bloc.state.numResults));
    expect(bloc.state.totalResults, 120);
    expect(bloc.state.isLoading, isFalse);
    expect(tester.takeException(), isNull);
  }, skip: !ready);
}

// מעכב רק את המשך הזרם האמיתי; התוצאות, הספירות וה-state נוצרים בקוד הייצור.
class _PausedRustOperations extends RustSearchEngineOperations {
  _PausedRustOperations(super.engine);

  final resume = Completer<void>();
  bool pauseNext = false;

  @override
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    var paused = false;
    await for (final update in super.searchStreamWithCounts(
      request,
      chunkSize: chunkSize,
    )) {
      yield update;
      if (pauseNext && !paused && update.results.isNotEmpty) {
        paused = true;
        await resume.future;
      }
    }
  }
}
