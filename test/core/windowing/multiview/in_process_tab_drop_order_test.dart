import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

class _MemoryTabsRepository extends TabsRepository {
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int index) async {}
  @override
  Future<void> flushPendingWrites() async {}
}

class _NavigationBloc extends Cubit<NavigationState> implements NavigationBloc {
  _NavigationBloc() : super(NavigationState.initial(false));
  @override
  void add(NavigationEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final split in [false, true]) {
    testWidgets('העברה שומרת מיקום אחרי יצירת חלונית אטית: split=$split', (
      tester,
    ) async {
      final drops = InProcessTabDrops();
      final tabs = TabsBloc(
        repository: _MemoryTabsRepository(),
        withCompanion: (tab) async {
          if (tab.title == 'incoming') {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          if (split && tab.title == 'incoming') {
            return CombinedTab(
              rightTab: tab,
              leftTab: ToolTab(toolId: 'builtin.calendar', title: 'companion'),
            );
          }
          return tab;
        },
      );
      final nav = _NavigationBloc();
      final before = ToolTab(toolId: 'builtin.calendar', title: 'existing');
      tabs.add(AddTab(before));
      await tester.pump();
      await tester.pump();
      expect(tabs.state.tabs, hasLength(1));
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<NavigationBloc>.value(value: nav),
          ],
          child: InProcessTabDropReceiver(
            drops: drops,
            child: const SizedBox(),
          ),
        ),
      );
      final source = ToolTab(toolId: 'builtin.gematria', title: 'incoming');
      expect(await drops.sendTabToWindow(1, source, index: 0), isTrue);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final actual = tabs.state.tabs.map((t) => t.title).toList();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await tabs.close();
        await nav.close();
      });
      expect(actual, [
        split ? 'משולב: incoming | companion' : 'incoming',
        'existing',
      ]);
    });
  }
  test('הכנסה מפורשת ברקע משמרת את הכרטיסיה הנוכחית', () async {
    final tabs = TabsBloc(
      repository: _MemoryTabsRepository(),
      withCompanion: (tab) async => tab,
    );
    final existing = ToolTab(toolId: 'builtin.calendar', title: 'קיים');
    tabs.add(AddTab(existing));
    await tabs.stream.firstWhere((state) => state.tabs.length == 1);
    tabs.add(
      AddTab(
        ToolTab(toolId: 'builtin.gematria', title: 'חדש'),
        index: 0,
        inBackground: true,
      ),
    );
    await tabs.stream.firstWhere((state) => state.tabs.length == 2);
    expect(tabs.state.currentTab, same(existing));
    expect(tabs.state.currentTabIndex, 1);
    await tabs.close();
  });

  test('שחרור מקור אחרי העברה משאיר את מצב התוסף ביעד', () async {
    final source = ToolTab(toolId: 'org.example.plugin', title: 'plugin');
    final key = (pluginId: source.toolId, instanceId: source.instanceId);
    final store = PluginRestoreStateStore.instance;
    store.set(key, {'draft': 'content'});
    ToolTab? received;
    final drops = InProcessTabDrops();
    final state = ExternalTabDragState();
    drops.register(
      AppWindowId.primary,
      InProcessTabDropTarget(
        dragState: state,
        devicePixelRatio: () => 1,
        receive: (tab, index) {
          received = tab as ToolTab;
          return true;
        },
      ),
    );
    expect(await drops.sendTabToWindow(1, source), isTrue);
    source.dispose();
    final json = received!.toJson();
    received!.dispose();
    state.drag.dispose();
    state.dropIndex.dispose();
    expect(json['pluginRestoreState'], isNotNull);
  });

  test('יעד שדוחה העברה משאיר את מצב התוסף במקור', () async {
    final source = ToolTab(toolId: 'org.example.plugin', title: 'plugin');
    PluginRestoreStateStore.instance.set(
      (pluginId: source.toolId, instanceId: source.instanceId),
      {'draft': 'content'},
    );
    final state = ExternalTabDragState();
    final drops = InProcessTabDrops();
    drops.register(
      AppWindowId.primary,
      InProcessTabDropTarget(
        dragState: state,
        devicePixelRatio: () => 1,
        receive: (tab, index) => false,
      ),
    );
    expect(await drops.sendTabToWindow(1, source), isFalse);
    expect(source.toJson()['pluginRestoreState'], contains('content'));
    source.dispose();
    state.drag.dispose();
    state.dropIndex.dispose();
  });
}
