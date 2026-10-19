import 'dart:async';
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_role.dart';
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
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:window_manager/window_manager.dart' show TitleBarStyle;
import '../test_helpers/memory_cache_provider.dart';

void main() {
  tz.initializeTimeZones();
  late Directory dataRoot;
  setUpAll(() async {
    registerFallbackValue(DropOrphanedIndexEntries(Library(categories: [])));
    dataRoot = await Directory.systemTemp.createTemp('main-window-load-test-');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
  });
  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  testWidgets('טעינת ספרייה שנכשלה אינה מפילה שגיאה לא מטופלת (#2469)', (
    tester,
  ) async {
    final catalog = Completer<Library>();
    final harness = await _pumpMainWindow(tester, catalog.future);
    harness.libraryChanges.add(
      harness.initialState.copyWith(isLoading: false, error: 'load failed'),
    );
    await tester.pump();
    catalog.completeError(StateError('catalog build failed'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verifyNever(() => harness.indexing.add(any()));
  });

  testWidgets('טעינת ספרייה שהצליחה מפעילה את החלטת האינדוקס', (tester) async {
    final harness = await _pumpMainWindow(
      tester,
      Future.value(Library(categories: [])),
    );
    harness.libraryChanges.add(harness.initialState.copyWith(isLoading: false));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verify(
      () => harness.indexing.add(any(that: isA<ReconcileHiddenIndex>())),
    ).called(1);
  });

  testWidgets('רענון ספרייה שנכשל אינו מפיל שגיאה לא מטופלת', (tester) async {
    final catalog = Completer<Library>();
    final harness = await _pumpMainWindow(
      tester,
      catalog.future,
      isLoading: false,
    );
    harness.libraryChanges.add(
      harness.initialState.copyWith(
        error: 'refresh failed',
        failedRefreshRequestIds: {7},
      ),
    );
    await tester.pump();
    catalog.completeError(StateError('catalog build failed'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    verifyNever(() => harness.indexing.add(any()));
  });
}

class _Harness {
  _Harness(this.libraryChanges, this.initialState, this.indexing);

  final StreamController<LibraryState> libraryChanges;
  final LibraryState initialState;
  final _IndexingBloc indexing;
}

Future<_Harness> _pumpMainWindow(
  WidgetTester tester,
  Future<Library> catalog, {
  bool isLoading = true,
}) async {
  await Settings.init(cacheProvider: MemoryCacheProvider());
  final oldSecondary = WindowRole.isSecondary;
  final oldOpenedWithTab = WindowRole.openedWithTab;
  WindowRole.isSecondary = true;
  WindowRole.openedWithTab = true;
  DataRepository.instance.library = catalog;
  // הבדיקה מאזינה בעצמה לכשל; כאן רק מונעים שה-Future המקורי ידווח כלא מטופל.
  DataRepository.instance.library.ignore();
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  final navigation = _NavigationBloc();
  whenListen(
    navigation,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.reading),
  );
  final focus = FocusRepository();
  final workStatus = WorkStatusCubit();
  final settings = _SettingsBloc();
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(isOfflineMode: true),
  );
  final indexing = _IndexingBloc();
  whenListen(
    indexing,
    const Stream<IndexingState>.empty(),
    initialState: IndexingInitial(),
  );
  final history = _HistoryBloc();
  whenListen(
    history,
    const Stream<HistoryState>.empty(),
    initialState: HistoryLoaded([]),
  );
  final initialState = LibraryState(
    library: Library(categories: []),
    isLoading: isLoading,
  );
  final libraryChanges = StreamController<LibraryState>.broadcast();
  final library = _LibraryBloc();
  whenListen(library, libraryChanges.stream, initialState: initialState);
  final tabs = _TabsBloc();
  whenListen(
    tabs,
    const Stream<TabsState>.empty(),
    initialState: TabsState.initial(),
  );
  final workspace = _WorkspaceBloc();
  whenListen(
    workspace,
    const Stream<WorkspaceState>.empty(),
    initialState: const WorkspaceState(workspaces: []),
  );
  final pluginSystem = _PluginSystemBloc();
  whenListen(
    pluginSystem,
    const Stream<PluginSystemState>.empty(),
    initialState: const PluginSystemLoaded([]),
  );
  final libraryUpdate = _LibraryUpdateBloc();
  whenListen(
    libraryUpdate,
    const Stream<LibraryUpdateState>.empty(),
    initialState: const LibraryUpdateState(),
  );

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await libraryChanges.close();
    for (final bloc in [
      navigation,
      settings,
      indexing,
      history,
      library,
      tabs,
      workspace,
      pluginSystem,
      libraryUpdate,
      workStatus,
    ]) {
      await bloc.close();
    }
    DataRepository.instance.invalidateLibraryCache();
    WindowRole.isSecondary = oldSecondary;
    WindowRole.openedWithTab = oldOpenedWithTab;
    await tester.binding.setSurfaceSize(null);
  });
  const window = _FakeWindow(AppWindowId('test-window'));
  await tester.pumpWidget(
    AppWindowScope(
      controller: window,
      geometry: window,
      child: RepositoryProvider<FocusRepository>.value(
        value: focus,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<NavigationBloc>.value(value: navigation),
            BlocProvider<WorkStatusCubit>.value(value: workStatus),
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<IndexingBloc>.value(value: indexing),
            BlocProvider<HistoryBloc>.value(value: history),
            BlocProvider<LibraryBloc>.value(value: library),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<WorkspaceBloc>.value(value: workspace),
            BlocProvider<PluginSystemBloc>.value(value: pluginSystem),
            BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdate),
          ],
          child: RepositoryProvider<SettingsRepository>(
            create: (_) => SettingsRepository(),
            child: const MaterialApp(home: MainWindowScreen()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(libraryChanges, initialState, indexing);
}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _IndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _TabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

class _WorkspaceBloc extends MockBloc<WorkspaceEvent, WorkspaceState>
    implements WorkspaceBloc {}

class _PluginSystemBloc extends MockBloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {}

class _LibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _FakeWindow implements AppWindowController, AppWindowGeometry {
  const _FakeWindow(this.id);

  @override
  final AppWindowId id;

  @override
  Future<void> center() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> quitApplication() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<Rect> getBounds() async => Rect.zero;
  @override
  Future<bool> isFullScreen() async => false;
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<bool> isVisible() async => true;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setBounds(Rect bounds) async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setProgressBar(double progress) async {}
  @override
  Future<void> setSize(Size size) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}
