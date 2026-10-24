import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = PluginRestoreStateStore.instance;
  late Directory directory;
  late UserStateDatabase database;
  late TabsRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = await Directory.systemTemp.createTemp('tool-restore-ownership');
    database = UserStateDatabase.openAt('${directory.path}/user_state.db');
    await database.database;
    repository = TabsRepository(
      sessions: WindowSessionStore(database: database),
    );
  });

  tearDown(() async {
    database.close();
    await directory.delete(recursive: true);
  });

  for (final split in [false, true]) {
    for (final savedState in [false, true]) {
      test(
        'ניקוי עץ ישן שומר מצב מופע משוחזר: split=$split saved=$savedState',
        () async {
          final source = ToolTab(toolId: 'ownership.plugin', title: 'מקור');
          final other = ToolTab(toolId: 'ownership.plugin', title: 'חלונית');
          final initial = split
              ? CombinedTab(rightTab: source, leftTab: other)
              : source;
          if (savedState) {
            store.set(
              (pluginId: source.toolId, instanceId: source.instanceId),
              {'screen': 'saved'},
            );
          }
          await repository.saveTabs([initial], 0);
          initial.dispose();
          if (!split) other.dispose();
          final started = Completer<void>();
          final release = Completer<void>();
          final old = TabsBloc(
            repository: repository,
            withCompanion: (tab) async {
              started.complete();
              await release.future;
              return tab;
            },
          )..add(LoadTabs());
          await old.stream.firstWhere((state) => state.tabs.isNotEmpty);
          final oldTool = split
              ? (old.state.tabs.single as CombinedTab).rightTab as ToolTab
              : old.state.tabs.single as ToolTab;
          final pending = ToolTab(
            toolId: 'ownership.plugin',
            title: 'פתיחה ממתינה',
          );
          final pendingKey = (
            pluginId: pending.toolId,
            instanceId: pending.instanceId,
          );
          store.set(pendingKey, {'screen': 'pending'});
          old.add(AddTab(pending));
          await started.future;
          final closing = old.close();
          final fresh = TabsBloc(repository: repository)..add(LoadTabs());
          await fresh.stream.firstWhere((state) => state.tabs.isNotEmpty);
          final freshTool = split
              ? (fresh.state.tabs.single as CombinedTab).rightTab as ToolTab
              : fresh.state.tabs.single as ToolTab;
          final freshKey = (
            pluginId: freshTool.toolId,
            instanceId: freshTool.instanceId,
          );
          expect(
            store.stateOf(freshKey),
            savedState ? {'screen': 'saved'} : isNull,
          );
          store.set(freshKey, {'screen': 'fresh'});
          release.complete();
          await closing;
          try {
            expect(store.stateOf(freshKey), {'screen': 'fresh'});
            expect(freshTool.instanceId, isNot(oldTool.instanceId));
            expect(store.has(pendingKey), isFalse);
          } finally {
            await fresh.close();
          }
        },
      );
    }
  }

  test('טעינת snapshot משמרת זהות ואינה זורעת רשומות runtime נוספות', () async {
    final source = ToolTab(toolId: 'ownership.plugin', title: 'snapshot');
    final key = (pluginId: source.toolId, instanceId: source.instanceId);
    store.set(key, {'screen': 'snapshot'});
    await repository.saveTabs([source], 0);
    final count = store.length;
    final first = repository.loadTabs().single as ToolTab;
    final second = repository.loadTabs().single as ToolTab;
    expect(
      [first.instanceId, second.instanceId],
      [source.instanceId, source.instanceId],
    );
    expect(store.length, count);
    first.dispose();
    second.dispose();
    source.dispose();
  });

  test('העברה מנתקת זהות בכל עומק של פיצול שמור', () {
    final original = ToolTab(toolId: 'ownership.plugin', title: 'פנימי');
    addTearDown(original.dispose);
    final key = (pluginId: original.toolId, instanceId: original.instanceId);
    store.set(key, {'screen': 'transfer'});
    final nested = OpenedTab.fromJson({
      'type': 'CombinedTab',
      'rightTab': {
        'type': 'CombinedTab',
        'rightTab': original.toJson(),
        'leftTab': ToolTab(toolId: 'builtin.calendar', title: 'לוח').toJson(),
      },
      'leftTab': ToolTab(toolId: 'builtin.gematria', title: 'גימטריה').toJson(),
    });
    final transferred = OpenedTab.fromJson(nested.toTransferJson());
    nested.dispose();
    final normalized = flattenRestoredSplits([transferred], currentIndex: 0);
    final tool = (normalized.tabs.first as CombinedTab).rightTab as ToolTab;
    final transferredKey = (pluginId: tool.toolId, instanceId: tool.instanceId);
    expect(tool.instanceId, isNot(original.instanceId));
    expect(store.stateOf(transferredKey), {'screen': 'transfer'});
    for (final tab in normalized.tabs) {
      tab.dispose();
    }
  });
}
