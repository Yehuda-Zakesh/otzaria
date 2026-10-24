import 'dart:async';

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
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import 'package:otzaria/tabs/tabs_repository.dart';

import '../../../test_helpers/memory_cache_provider.dart';

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
  setUp(() async => Settings.init(cacheProvider: MemoryCacheProvider()));
  for (final split in [false, true]) {
    testWidgets(
      'יעד עסוק מסרב, ואחרי פתיחה נשמרים פיצול ומיקום: split=$split',
      (
        tester,
      ) async {
        final drops = InProcessTabDrops();
        final tabs = TabsBloc(
          repository: _MemoryTabsRepository(),
          withCompanion: (tab) async {
            if (tab.title == 'pending') {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            if (split && tab.title == 'pending') {
              return CombinedTab(
                rightTab: tab,
                leftTab: ToolTab(
                  toolId: 'builtin.calendar',
                  title: 'companion',
                ),
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
        tabs.add(AddTab(ToolTab(toolId: 'builtin.calendar', title: 'pending')));
        await tester.pump();
        final OpenedTab source = split
            ? CombinedTab(
                rightTab: ToolTab(
                  toolId: 'builtin.gematria',
                  title: 'incoming',
                ),
                leftTab: ToolTab(
                  toolId: 'builtin.calendar',
                  title: 'companion',
                ),
              )
            : ToolTab(toolId: 'builtin.gematria', title: 'incoming');
        expect(await drops.sendTabToWindow(1, source, index: 0), isFalse);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pump();
        expect(await drops.sendTabToWindow(1, source, index: 0), isTrue);
        final actual = tabs.state.tabs.map((t) => t.title).toList();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await tabs.close();
          await nav.close();
        });
        expect(actual, [
          split ? 'משולב: incoming | companion' : 'incoming',
          'existing',
          split ? 'משולב: pending | companion' : 'pending',
        ]);
        source.dispose();
      },
    );
  }
  test('העברת ספר ראשי אינה פותחת שוב מלווה שהמשתמש סגר', () async {
    final tabs = TabsBloc(
      repository: _MemoryTabsRepository(),
      withCompanion: (_) async =>
          throw StateError('transfer must preserve its panes'),
    );
    final primary = TextBookTab(book: TextBook(title: 'משנה ברורה'), index: 0);
    expect(tabs.receiveTransferredTab(primary), isTrue);
    expect(tabs.state.tabs, [same(primary)]);
    expect(tabs.state.currentTabIndex, 0);
    await tabs.close();
  });

  test('קליטה מסורבת בזמן שחזור שעדיין ממתין בתור', () async {
    final tabs = TabsBloc(repository: _MemoryTabsRepository())..add(LoadTabs());
    final incoming = ToolTab(toolId: 'builtin.calendar', title: 'לא נקלט');
    expect(tabs.receiveTransferredTab(incoming), isFalse);
    incoming.dispose();
    await Future<void>.delayed(Duration.zero);
    await tabs.close();
  });

  test('קליטה מסורבת כשכבר נשלחה החלפת שולחן', () async {
    final tabs = TabsBloc(repository: _MemoryTabsRepository());
    final replacement = ToolTab(toolId: 'builtin.calendar', title: 'שולחן חדש');
    tabs.add(ReplaceAllTabs([replacement], 0));
    final incoming = ToolTab(toolId: 'builtin.gematria', title: 'נשאר במקור');
    expect(tabs.receiveTransferredTab(incoming), isFalse);
    incoming.dispose();
    await tabs.stream.firstWhere((state) => state.tabs.length == 1);
    expect(tabs.state.tabs, [same(replacement)]);
    await tabs.close();
  });

  for (final operation in ['closeAll', 'closeOther', 'adopt']) {
    test('קליטה מסורבת בזמן שינוי רשימת הכרטיסיות: $operation', () async {
      final tabs = TabsBloc(
        repository: _MemoryTabsRepository(),
        disposeDelay: Duration.zero,
      );
      final before = ToolTab(toolId: 'builtin.calendar', title: 'קיים');
      tabs.add(AddTab(before));
      await tabs.stream.firstWhere((state) => state.tabs.length == 1);
      await Future<void>.delayed(Duration.zero);
      final event = switch (operation) {
        'closeAll' => CloseAllTabs(),
        'closeOther' => CloseOtherTabs(before),
        _ => AdoptTab(ToolTab(toolId: 'builtin.gematria', title: 'מאומץ')),
      };
      tabs.add(event);
      final incoming = ToolTab(toolId: 'builtin.gematria', title: 'נשאר במקור');
      expect(tabs.receiveTransferredTab(incoming), isFalse);
      incoming.dispose();
      await Future<void>.delayed(Duration.zero);
      await tabs.close();
      await Future<void>.delayed(Duration.zero);
    });
  }

  for (final openOrFocus in [false, true]) {
    test(
      'סגירה מנקזת פתיחה ממתינה ומשחררת קוראים: openOrFocus=$openOrFocus',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final primary = TextBookTab(
          book: TextBook(title: 'משנה ברורה'),
          index: 0,
        );
        final companion = TextBookTab(
          book: TextBook(title: 'ביאור הלכה'),
          index: 0,
        );
        final readers = [primary.bloc, companion.bloc];
        final tabs = TabsBloc(
          repository: _MemoryTabsRepository(),
          withCompanion: (tab) async {
            started.complete();
            await release.future;
            return CombinedTab(rightTab: tab, leftTab: companion);
          },
        );
        tabs.add(openOrFocus ? OpenOrFocusTab(primary) : AddTab(primary));
        await started.future;
        final closing = tabs.close();
        final refused = ToolTab(toolId: 'builtin.calendar', title: 'מסורב');
        expect(tabs.isClosed, isFalse);
        expect(tabs.receiveTransferredTab(refused), isFalse);
        refused.dispose();
        release.complete();
        await closing;
        await Future<void>.delayed(Duration.zero);
        expect(readers.every((reader) => reader.isClosed), isTrue);
        expect(tabs.close(), same(closing));
      },
    );
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
