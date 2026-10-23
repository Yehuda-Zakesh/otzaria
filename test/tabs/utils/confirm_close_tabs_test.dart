import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return <OpenedTab>[];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  ToolTab pluginTab(String id, String title) =>
      ToolTab(toolId: id, title: title, instanceId: 'inst-$id');

  TextBookTab textTab() =>
      TextBookTab(book: TextBook(title: 'ברכות'), index: 0);

  group('unsavedPluginTabs', () {
    late PluginUnsavedChangesRegistry registry;

    setUp(() => registry = PluginUnsavedChangesRegistry.forTesting());

    test('מחזיר רק כרטיסיות תוסף שסימנו שינויים, עם ההודעה שלהן', () {
      final dirty = pluginTab('p.editor', 'עורך');
      final clean = pluginTab('p.other', 'אחר');
      registry.set(
        (pluginId: 'p.editor', instanceId: 'inst-p.editor'),
        hasChanges: true,
        message: 'הטיוטה תאבד',
      );

      final result = unsavedPluginTabs([
        textTab(),
        clean,
        dirty,
      ], registry: registry);

      expect(result, hasLength(1));
      expect(result.single.tab, same(dirty));
      expect(result.single.message, 'הטיוטה תאבד');
    });

    test('כלי מובנה אינו נחשב תוסף גם אם מזהה המופע רשום', () {
      final builtIn = ToolTab(
        toolId: 'builtin.calendar',
        title: 'לוח שנה',
        instanceId: 'x',
      );
      registry.set(
        (pluginId: 'builtin.calendar', instanceId: 'x'),
        hasChanges: true,
      );
      expect(unsavedPluginTabs([builtIn], registry: registry), isEmpty);
    });

    test('מוצא חלונית תוסף בתוך כרטיסיה מפוצלת', () {
      final dirty = pluginTab('p.editor', 'עורך');
      registry.set(
        (pluginId: 'p.editor', instanceId: 'inst-p.editor'),
        hasChanges: true,
      );
      final combined = CombinedTab(rightTab: textTab(), leftTab: dirty);

      final result = unsavedPluginTabs([combined], registry: registry);
      expect(result.single.tab, same(dirty));
      expect(result.single.message, isNull);
    });
  });

  test('unsavedChangesDialogContent — שורה לכרטיסיה ואחריה ההודעה', () {
    final content = unsavedChangesDialogContent([
      (tab: pluginTab('a', 'עורך'), message: 'הטיוטה תאבד'),
      (tab: pluginTab('b', 'טבלה'), message: null),
    ]);
    expect(
      content,
      'ב"עורך" יש שינויים שלא נשמרו.\nהטיוטה תאבד\nב"טבלה" יש שינויים שלא נשמרו.',
    );
  });

  group('confirmCloseTabs', () {
    final key = (pluginId: 'p.editor', instanceId: 'inst-p.editor');

    tearDown(() => PluginUnsavedChangesRegistry.instance.removeInstance(key));

    Future<Future<bool>> pump(WidgetTester tester, ToolTab tab) async {
      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = confirmCloseTabs(context, [tab]),
              child: const Text('close'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('בלי שינויים — מאשר מיד בלי דיאלוג', (tester) async {
      final result = await pump(tester, pluginTab('p.editor', 'עורך'));
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
      expect(await result, isTrue);
    });

    testWidgets('עם שינויים — הדיאלוג מציג את ההודעה וביטול מחזיר false', (
      tester,
    ) async {
      PluginUnsavedChangesRegistry.instance.set(
        key,
        hasChanges: true,
        message: 'הטיוטה תאבד',
      );
      final result = await pump(tester, pluginTab('p.editor', 'עורך'));

      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      expect(find.textContaining('הטיוטה תאבד'), findsOneWidget);

      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('"סגור בכל זאת" מחזיר true', (tester) async {
      PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
      final result = await pump(tester, pluginTab('p.editor', 'עורך'));

      await tester.tap(find.text(unsavedChangesCloseAnyway));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });

  group('confirmAppCloseWithUnsavedChanges', () {
    final key = (pluginId: 'p.editor', instanceId: 'inst-p.editor');
    late TabsBloc tabsBloc;

    setUp(() => tabsBloc = TabsBloc(repository: _FakeTabsRepository()));
    tearDown(() async {
      PluginUnsavedChangesRegistry.instance.removeInstance(key);
      await tabsBloc.close();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: tabsBloc,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      tabsBloc.add(ReplaceAllTabs([pluginTab('p.editor', 'עורך')], 0));
      await tester.pump();
    }

    testWidgets('בלי שינויים — מאשר בלי דיאלוג', (tester) async {
      await pumpApp(tester);
      expect(await confirmAppCloseWithUnsavedChanges(), isTrue);
      await tester.pump();
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
    });

    testWidgets('שני מאזינים מקבלים את אותה תשובה מדיאלוג אחד', (
      tester,
    ) async {
      await pumpApp(tester);
      PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);

      final first = confirmAppCloseWithUnsavedChanges();
      final second = confirmAppCloseWithUnsavedChanges();
      await tester.pumpAndSettle();

      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      expect(find.text(unsavedChangesAppCloseSubtitle), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();

      expect(await first, isFalse);
      expect(await second, isFalse);

      // אחרי שהדיאלוג נסגר, קריאה חדשה פותחת דיאלוג חדש.
      final third = confirmAppCloseWithUnsavedChanges();
      await tester.pumpAndSettle();
      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      await tester.tap(find.text(unsavedChangesCloseAnyway));
      await tester.pumpAndSettle();
      expect(await third, isTrue);
    });
  });

  group('confirmAppCloseWithUnsavedChanges עם חלונות Dart', () {
    final key = (pluginId: 'p.editor', instanceId: 'inst-p.editor');
    late TabsBloc mainTabs;
    late TabsBloc viewTabs;
    late AppWindowKeys view;

    setUp(() {
      MultiViewMode.debugOverride = true;
      mainTabs = TabsBloc(repository: _FakeTabsRepository());
      viewTabs = TabsBloc(repository: _FakeTabsRepository());
      view = AppWindowKeys(id: const AppWindowId('window-view-2'));
      AppWindowKeys.register(view);
    });
    tearDown(() async {
      MultiViewMode.debugOverride = null;
      AppWindowKeys.resetForTest();
      PluginUnsavedChangesRegistry.instance.removeInstance(key);
      await mainTabs.close();
      await viewTabs.close();
    });

    Widget window(AppWindowKeys keys, TabsBloc tabs) => BlocProvider.value(
      value: tabs,
      child: MaterialApp(navigatorKey: keys.navigator, home: const SizedBox()),
    );

    Future<void> pumpWindows(
      WidgetTester tester, {
      bool dirtyMain = true,
    }) async {
      final primary = AppWindowKeys.registered.firstWhere(
        (keys) => keys.id == AppWindowId.primary,
      );
      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(child: window(primary, mainTabs)),
            Expanded(child: window(view, viewTabs)),
          ],
        ),
      );
      if (dirtyMain) {
        mainTabs.add(ReplaceAllTabs([pluginTab('p.editor', 'עורך')], 0));
        await tester.pump();
        PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
      }
    }

    testWidgets('סגירת הראשי כשחלון Dart פתוח היא "סגירת החלון", בחלון שנסגר', (
      tester,
    ) async {
      await pumpWindows(tester);
      final primary = AppWindowKeys.registered.firstWhere(
        (keys) => keys.id == AppWindowId.primary,
      );
      AppWindowKeys.activate(view);
      final result = confirmAppCloseWithUnsavedChanges(window: primary);
      await tester.pumpAndSettle();

      expect(find.text(unsavedChangesWindowCloseSubtitle), findsOneWidget);
      expect(find.textContaining('עורך'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    for (final dirtyInMain in [false, true]) {
      testWidgets(
        'יציאה מלאה אוספת תוספים מכל חלון ונשארת במקור: dirtyInMain=$dirtyInMain',
        (tester) async {
          await pumpWindows(tester, dirtyMain: false);
          final primary = AppWindowKeys.registered.firstWhere(
            (keys) => keys.id == AppWindowId.primary,
          );
          final dirtyTabs = dirtyInMain ? mainTabs : viewTabs;
          final emptyTabs = dirtyInMain ? viewTabs : mainTabs;
          dirtyTabs.add(
            ReplaceAllTabs([pluginTab('p.editor', 'טיוטה מחלון אחר')], 0),
          );
          emptyTabs.add(ReplaceAllTabs([], 0));
          await tester.pump();
          PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
          if (dirtyInMain) {
            await tester.pumpWidget(
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(child: Offstage(child: window(primary, mainTabs))),
                  Expanded(child: window(view, viewTabs)),
                ],
              ),
            );
          }
          final origin = dirtyInMain ? view : primary;
          AppWindowKeys.activate(origin);
          final first = confirmAppCloseWithUnsavedChanges(allWindows: true);
          final second = confirmAppCloseWithUnsavedChanges(allWindows: true);
          AppWindowKeys.activate(dirtyInMain ? primary : view);
          await tester.pumpAndSettle();
          expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
          expect(find.textContaining('טיוטה מחלון אחר'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(origin.navigator),
              matching: find.text(unsavedChangesDialogTitle),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('ביטול'));
          await tester.pumpAndSettle();
          expect(await first, isFalse);
          expect(await second, isFalse);
          expect(dirtyTabs.state.tabs, hasLength(1));
        },
      );
    }

    testWidgets('חלון Dart האחרון שנסגר אינו סופר את עצמו', (tester) async {
      await pumpWindows(tester);
      viewTabs.add(ReplaceAllTabs([pluginTab('p.editor', 'עורך')], 0));
      await tester.pump();
      AppWindowKeys.activate(view);
      final result = confirmAppCloseWithUnsavedChanges();
      await tester.pumpAndSettle();

      expect(find.text(unsavedChangesAppCloseSubtitle), findsOneWidget);
      await tester.tap(find.text(unsavedChangesCloseAnyway));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });
}
