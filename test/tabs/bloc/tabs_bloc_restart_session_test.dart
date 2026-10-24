import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late UserStateDatabase database;
  late WindowSessionStore store;
  late WindowTabsSession session;
  late TabsRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = await Directory.systemTemp.createTemp('tabs-restart-session');
    database = UserStateDatabase.openAt('${directory.path}/state.db');
    await database.database;
    store = WindowSessionStore(database: database);
    session = WindowTabsSession(slot: () => 1);
    repository = TabsRepository(sessions: store, window: session);
    final source = ToolTab(toolId: 'source', title: 'מקור');
    await repository.saveTabs([source], 0);
    source.dispose();
  });

  tearDown(() async {
    await repository.flushPendingWrites();
    database.close();
    await directory.delete(recursive: true);
  });

  Future<List<String>> savedTitles() async => [
    for (final tab in jsonDecode((await store.load(1))!.tabsJson) as List)
      tab['title'] as String,
  ];

  for (final restart in [false, true]) {
    test(
      'סגירה מסיימת פתיחה ממתינה בלי לדרוס עץ חדש: restart=$restart',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final old = TabsBloc(
          repository: repository,
          session: session,
          withCompanion: (tab) async {
            started.complete();
            await release.future;
            return tab;
          },
        )..add(LoadTabs());
        await old.stream.firstWhere((state) => state.tabs.isNotEmpty);
        old.add(AddTab(ToolTab(toolId: 'pending', title: 'ממתין')));
        await started.future;
        final closing = old.close();
        TabsBloc? fresh;
        if (restart) {
          fresh = TabsBloc(repository: repository, session: session)
            ..add(LoadTabs());
          await fresh.stream.firstWhere((state) => state.tabs.isNotEmpty);
          fresh.add(AddTab(ToolTab(toolId: 'fresh', title: 'חדש')));
          await fresh.stream.firstWhere((state) => state.tabs.length == 2);
          await Future<void>.delayed(Duration.zero);
          expect(await savedTitles(), ['מקור', 'חדש']);
        }
        release.complete();
        await closing;
        try {
          expect(old.state.tabs.map((tab) => tab.title), ['מקור', 'ממתין']);
          expect(
            await savedTitles(),
            restart ? ['מקור', 'חדש'] : ['מקור', 'ממתין'],
          );
        } finally {
          await fresh?.close();
        }
      },
    );
  }

  test('עץ ישן אינו משנה אינדקס אחרי שהעץ החדש כבר שמר', () async {
    final second = ToolTab(toolId: 'second', title: 'שני');
    final source = repository.loadTabs().single;
    await repository.saveTabs([source, second], 0);
    source.dispose();
    second.dispose();
    final old = TabsBloc(repository: repository, session: session)
      ..add(LoadTabs());
    await old.stream.firstWhere((state) => state.tabs.length == 2);
    final fresh = TabsBloc(repository: repository, session: session)
      ..add(LoadTabs());
    await fresh.stream.firstWhere((state) => state.tabs.length == 2);
    fresh.add(AddTab(ToolTab(toolId: 'fresh', title: 'חדש')));
    await fresh.stream.firstWhere((state) => state.tabs.length == 3);
    await Future<void>.delayed(Duration.zero);
    expect((await store.load(1))!.currentIndex, 2);
    old.add(const SetCurrentTab(1));
    await old.stream.firstWhere((state) => state.currentTabIndex == 1);
    await repository.flushPendingWrites();
    try {
      expect((await store.load(1))!.currentIndex, 2);
    } finally {
      await old.close();
      await fresh.close();
    }
  });

  test('רכישת העץ החדש אינה מבטלת שמירת אינדקס שכבר ממתינה', () async {
    final source = repository.loadTabs().single;
    final second = ToolTab(toolId: 'second', title: 'שני');
    await repository.saveTabs([source, second], 0);
    await repository.saveCurrentTabIndex([source, second], 1);
    source.dispose();
    second.dispose();
    final fresh = TabsBloc(repository: repository, session: session);
    try {
      await repository.flushPendingWrites();
      expect((await store.load(1))!.currentIndex, 1);
    } finally {
      await fresh.close();
    }
  });
}
