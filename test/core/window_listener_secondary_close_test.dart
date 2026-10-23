import 'dart:async';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../test_helpers/controllable_correction_draft_repository.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.secondaryclose';

/// סגירה מנומסת שומרת סשן לעדכון ומוחקת סשן בסגירת X רגילה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _FakeRunner runner;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    WindowBus.namespace = _namespace;
    WindowRole.isSecondary = false;
    // ה-runner מדומה כדי לבדוק את מסלול ריבוי החלונות בכל פלטפורמה.
    MultiWindowService.debugSupportedOverride = true;
    runner = _FakeRunner()..install();
    tmp = Directory.systemTemp.createTempSync('otzaria_secclose_');
    AppPaths.debugProfileDataRootPath = tmp.path;
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
    TabsRepository.debugSessions = sessions;
  });

  tearDown(() async {
    AppWindowListener.prepareUpdateForClose = null;
    AppPaths.debugProfileDataRootPath = null;
    TabsRepository.debugSessions = null;
    MultiWindowService.closingAll = false;
    database.close();
    runner.uninstall();
    MultiWindowService.debugSupportedOverride = null;
    MultiWindowService.correctionQuitRequestTimeout = const Duration(
      seconds: 6,
    );
    WindowRole.isSecondary = false;
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('סגירת חלון בלי כיבוי התהליך משמרת canary', () async {
    WindowBus.instance.register();
    IndexingCrashCanary.start('${tmp.path}/index');
    final canary = IndexingCrashCanary.current!;
    canary.begin('id:crashing');
    addTearDown(canary.finish);
    await AppWindowListener().handleWindowClose();
    expect(runner.closeSelfCalls, 1);
    expect(
      IndexingCrashCanary.current,
      same(canary),
      reason: 'האינדוקס ממשיך במנוע החי לאחר הסתרת החלון',
    );
  });

  test('הכנת העדכון מסתיימת לפני flush וסגירה, גם באירוע כפול', () async {
    WindowBus.instance.register();
    final preparing = Completer<void>();
    final started = Completer<void>();
    final steps = <String>[];
    AppWindowListener.prepareUpdateForClose = () async {
      steps.add('prepare');
      started.complete();
      await preparing.future;
      steps.add('launched');
    };
    Future<void> flush() async => steps.add('flush');
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    final listener = AppWindowListener();
    final close = listener.handleWindowClose();
    await started.future;
    await listener.handleWindowClose();
    expect(steps, ['prepare']);
    expect(runner.closeSelfCalls, 0);

    preparing.complete();
    await close;
    expect(steps, ['prepare', 'launched', 'flush']);
    expect(runner.closeSelfCalls, 1);
  });

  test('סגירה שבוטלה אינה מכינה או משגרת עדכון', () async {
    var launches = 0;
    AppWindowListener.prepareUpdateForClose = () async => launches++;

    await AppWindowListener().handleWindowClose(canClose: () => false);

    expect(launches, 0);
    expect(runner.closeSelfCalls, 0);
  });

  testWidgets('כיבוי macOS נכשל בבטחה כשחלון מוסתר לא עונה', (tester) async {
    MultiWindowService.correctionQuitRequestTimeout = const Duration(
      milliseconds: 10,
    );
    WindowBus.instance.register();
    final peer = _FakeOwner(2, reply: false)..register();
    addTearDown(peer.dispose);
    final tab = ToolTab(toolId: 'p', title: 'תוסף', instanceId: 'i');
    await tester.pumpWidget(
      BlocProvider<TabsBloc>.value(
        value: _GuardTabs(tab),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const SizedBox(),
        ),
      ),
    );

    await tester.runAsync(
      () => AppWindowListener().handleWindowClose(quit: true),
    );

    expect(runner.closeSelfCalls, 0);
    expect(PluginCorrectionSessionService.instance.processQuitPending, isFalse);
  });

  test('סגירת הראשי ממתינה למסלול סגירה של חלון Dart', () async {
    MultiViewMode.debugOverride = true;
    WindowOpener.debugOverride = _TwoWindowsOpener();
    addTearDown(() {
      MultiViewMode.debugOverride = null;
      WindowOpener.debugOverride = null;
      WindowTabsSession.current.resume();
    });
    WindowBus.instance.register();
    final released = Completer<void>();
    final started = Completer<void>();
    final otherClose = ViewWindowOpener.instance.serializeClose(() async {
      started.complete();
      await released.future;
      return true;
    });
    await started.future;
    var prepared = false;
    AppWindowListener.prepareUpdateForClose = () async {
      prepared = true;
    };
    final mainClose = AppWindowListener().handleWindowClose();
    await Future<void>.delayed(Duration.zero);
    expect(prepared, isFalse);
    released.complete();
    await otherClose;
    await mainClose;
    expect(prepared, isTrue);
  });

  testWidgets(
    'יציאה מה-Dart האחרון מחליפה סגירת ראשי ממתינה גם כשהיציאה בוטלה',
    (tester) async {
      MultiViewMode.debugOverride = true;
      WindowOpener.debugOverride = _TwoWindowsOpener();
      MultiWindowService.correctionQuitRequestTimeout = const Duration(
        milliseconds: 10,
      );
      addTearDown(() {
        MultiViewMode.debugOverride = null;
        WindowOpener.debugOverride = null;
        WindowTabsSession.current.resume();
      });
      WindowBus.instance.register();
      final peer = _FakeOwner(2, reply: false)..register();
      addTearDown(peer.dispose);
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: _GuardTabs(
            ToolTab(toolId: 'p', title: 'טיוטה', instanceId: 'queued-quit'),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      var prepared = 0;
      AppWindowListener.prepareUpdateForClose = () async {
        prepared++;
      };
      await tester.runAsync(() async {
        final released = Completer<void>();
        final started = Completer<void>();
        final dartClose = ViewWindowOpener.instance.serializeClose(() async {
          started.complete();
          await released.future;
          return true;
        });
        await started.future;
        final listener = AppWindowListener();
        final mainClose = listener.handleWindowClose();
        await listener.quitFromLastViewWindow();
        released.complete();
        await dartClose;
        await mainClose;
      });
      expect(
        prepared,
        0,
        reason: 'אישור יציאה נכשל; סגירה רגילה ישנה אינה רצה אחריו',
      );
      expect(runner.closeSelfCalls, 0);
      expect(WindowTabsSession.current.slot, isNotNull);
    },
  );

  test('יציאה מפורשת בזמן סגירה פעילה ממתינה ונבדקת אחריה', () async {
    MultiViewMode.debugOverride = true;
    WindowOpener.debugOverride = _TwoWindowsOpener();
    addTearDown(() {
      MultiViewMode.debugOverride = null;
      WindowOpener.debugOverride = null;
      WindowTabsSession.current.resume();
    });
    WindowBus.instance.register();
    final prepared = Completer<void>();
    final released = Completer<void>();
    AppWindowListener.prepareUpdateForClose = () async {
      prepared.complete();
      await released.future;
    };
    final listener = AppWindowListener();
    final normal = listener.handleWindowClose();
    await prepared.future;
    var quitAttempts = 0;
    final quit = listener.handleWindowClose(
      quit: true,
      canClose: () {
        quitAttempts++;
        return false;
      },
    );
    expect(quitAttempts, 0);
    released.complete();
    await normal;
    await quit;
    expect(quitAttempts, 1);
    expect(runner.closeSelfCalls, 1);
  });

  testWidgets('עדכון בריבוי תצוגות מבקש יציאה מלאה ולא מסתיר רק את הראשי', (
    tester,
  ) async {
    MultiViewMode.debugOverride = true;
    WindowOpener.debugOverride = _TwoWindowsOpener();
    MultiWindowService.correctionQuitRequestTimeout = const Duration(
      milliseconds: 10,
    );
    addTearDown(() {
      MultiViewMode.debugOverride = null;
      WindowOpener.debugOverride = null;
      WindowTabsSession.current.resume();
    });
    WindowBus.instance.register();
    final peer = _FakeOwner(2, reply: false)..register();
    addTearDown(peer.dispose);
    final tab = ToolTab(toolId: 'p', title: 'תוסף', instanceId: 'update');
    await tester.pumpWidget(
      BlocProvider<TabsBloc>.value(
        value: _GuardTabs(tab),
        child: MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
      ),
    );
    MultiWindowService.closePeers();
    await tester.runAsync(() => AppWindowListener().handleWindowClose());
    expect(
      runner.closeSelfCalls,
      0,
      reason: 'חלון שלא אישר יציאה מונע את הכיבוי; הראשי נשאר גלוי',
    );
    expect(WindowTabsSession.current.slot, isNotNull);
    expect(MultiWindowService.closingAll, isFalse);
  });

  test('כשל בהכנת העדכון אינו נועל את ניסיון הסגירה הבא', () async {
    WindowBus.instance.register();
    final listener = AppWindowListener();
    AppWindowListener.prepareUpdateForClose = () async {
      throw StateError('preparation failed');
    };

    await expectLater(listener.handleWindowClose(), throwsStateError);
    expect(runner.closeSelfCalls, 0);

    AppWindowListener.prepareUpdateForClose = null;
    await listener.handleWindowClose();
    expect(runner.closeSelfCalls, 1);
  });

  test('חלון משני שאינו האחרון: flush רץ, הסשן נמחק, ורק הוא נסגר', () async {
    final owner = _FakeOwner(1)..register();
    addTearDown(owner.dispose);

    var flushed = false;
    Future<void> flush() async => flushed = true;
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    WindowRole.isSecondary = true;
    WindowBus.instance.register();
    // כרטיסיות שמורות בסשן של החלון הזה.
    await TabsRepository().saveTabs(const [], 0);
    final slot = WindowBus.instance.slot!;
    expect(await sessions.load(slot), isNotNull);

    await AppWindowListener().handleWindowClose();

    expect(flushed, isTrue, reason: 'הכתיבות התלויות נשטפו');
    expect(runner.closeSelfCalls, 1, reason: 'רק החלון הזה נסגר');
    expect(
      await sessions.load(slot),
      isNull,
      reason:
          'הסשן נמחק — בלעדיו `adoptOrphanWindowSessions` היה מחזיר '
          'בהפעלה הבאה כרטיסיות שהמשתמש סגר במכוון',
    );
  });

  test('החלון הראשון שאינו האחרון: הסשן שלו נמחק כמו של כל חלון', () async {
    // ⚠️ ההצדקה זהה לזו של חלון משני — הוא נסגר במכוון בעוד אחרים
    // פתוחים — ולכן הכרטיסיות שלו אינן "פתוחות" יותר.
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    await TabsRepository().saveTabs(const [], 0);

    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(await sessions.load(slot), isNull);
  });

  test(
    'ריבוי תצוגות: הראשי מוסתר כשחלונות Dart פתוחים, והסשן שלו מושהה',
    () async {
      MultiViewMode.debugOverride = true;
      WindowOpener.debugOverride = _TwoWindowsOpener();
      addTearDown(() {
        MultiViewMode.debugOverride = null;
        WindowOpener.debugOverride = null;
        WindowTabsSession.current.resume();
      });
      WindowBus.instance.register();
      final slot = WindowBus.instance.slot!;
      await TabsRepository().saveTabs(const [], 0);
      final closedBefore = ViewWindowOpener.instance.closedCountForTest;

      final listener = AppWindowListener();
      await listener.handleWindowClose();

      expect(runner.closeSelfCalls, 1, reason: 'הסתרה, לא יציאה (D1a)');
      expect(await sessions.load(slot), isNull);
      // ה-flush של החלון האחרון אינו כותב את הסשן שנמחק.
      expect(WindowTabsSession.current.slot, isNull);
      await TabsRepository().saveTabs(const [], 0);
      expect(await sessions.load(slot), isNull);
      expect(ViewWindowOpener.instance.closedCountForTest, closedBefore + 1);

      // הוצג שוב (Ctrl+Shift+T): שומר שוב.
      listener.onWindowFocus();
      expect(WindowTabsSession.current.slot, slot);
    },
  );

  test('סגירה לעדכון כשחלון אחר עוד פתוח: הסשן נשמר (issue #2095)', () async {
    // `closePeers` אינו ממתין, ולכן החלון שמתקין רואה עוד חלון פתוח.
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    await TabsRepository().saveTabs(const [], 0);

    MultiWindowService.closePeers();
    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(await sessions.load(slot), isNotNull);
  });

  test('X אחרי החזרת חלון שנסגר לעדכון מוחק את הסשן', () async {
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    final repository = TabsRepository();
    final listener = AppWindowListener();
    final tab = ToolTab(
      toolId: 'p.editor',
      title: 'עורך',
      instanceId: 'revived',
    );
    await repository.saveTabs([tab], 0);

    MultiWindowService.closePeers();
    await listener.handleWindowClose();
    expect(await sessions.load(slot), isNotNull);
    expect(await const MultiWindowService().restoreLastClosedWindow(), isTrue);
    await repository.saveTabs([tab], 0);
    await listener.handleWindowClose();

    expect(runner.closeSelfCalls, 2);
    expect(await sessions.adoptInto(slot == 1 ? 2 : 1), 0);
  });

  for (final cancellationCheck in [1, 2]) {
    test(
      'ביטול canClose בבדיקה $cancellationCheck אינו שומר כוונת עדכון',
      () async {
        WindowBus.instance.register();
        final slot = WindowBus.instance.slot!;
        await TabsRepository().saveTabs(const [], 0);
        final listener = AppWindowListener();
        var checks = 0;

        MultiWindowService.closePeers();
        await listener.handleWindowClose(
          canClose: () => ++checks < cancellationCheck,
        );
        expect(runner.closeSelfCalls, 0);
        expect(await sessions.load(slot), isNotNull);
        await listener.handleWindowClose();

        expect(runner.closeSelfCalls, 1);
        expect(await sessions.load(slot), isNull);
      },
    );
  }

  for (final beforeGuard in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets(
        'עדכון ${beforeGuard ? 'לפני' : 'בזמן'} שומר X ואז ${confirm ? 'אישור' : 'ביטול'}',
        (
          tester,
        ) async {
          WindowBus.instance.register();
          final slot = WindowBus.instance.slot!;
          final tab = ToolTab(
            toolId: 'p.editor',
            title: 'עורך',
            instanceId: 'guard',
          );
          final key = (pluginId: tab.toolId, instanceId: tab.instanceId);
          await tester.runAsync(() => TabsRepository().saveTabs([tab], 0));
          PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
          addTearDown(
            () => PluginUnsavedChangesRegistry.instance.removeInstance(key),
          );
          await tester.pumpWidget(
            BlocProvider<TabsBloc>.value(
              value: _GuardTabs(tab),
              child: MaterialApp(
                navigatorKey: navigatorKey,
                home: const SizedBox(),
              ),
            ),
          );
          addTearDown(() => tester.pumpWidget(const SizedBox()));
          final listener = AppWindowListener();
          if (beforeGuard) MultiWindowService.closePeers();
          final closing = listener.handleWindowClose();
          await tester.pumpAndSettle();
          expect(find.text(unsavedChangesDialogTitle), findsOneWidget);

          MultiWindowService.closePeers();
          final duplicate = listener.handleWindowClose();
          await tester.pump();
          expect(runner.closeSelfCalls, 0);
          expect(MultiWindowService.closingAll, isTrue);
          await tester.tap(
            find.text(confirm ? unsavedChangesCloseAnyway : 'ביטול'),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await closing;
            await duplicate;
          });
          expect(runner.closeSelfCalls, confirm ? 1 : 0);
          expect(await tester.runAsync(() => sessions.load(slot)), isNotNull);
          expect(MultiWindowService.closingAll, isFalse);

          PluginUnsavedChangesRegistry.instance.removeInstance(key);
          if (confirm) {
            expect(
              await const MultiWindowService().restoreLastClosedWindow(),
              isTrue,
            );
          }
          await tester.runAsync(() => listener.handleWindowClose());
          expect(await tester.runAsync(() => sessions.load(slot)), isNull);
        },
      );
    }
  }

  group('סשן תיקון בלשונית קורא', () {
    final service = PluginCorrectionSessionService.instance;
    final ended = <String>[];
    late Database draftDb;
    late ControllableCorrectionDraftRepository drafts;
    late TextBookTab tab;
    late String tabId;

    setUp(() {
      PluginCorrectionSessionService.flushTimeout = const Duration(
        milliseconds: 100,
      );
      draftDb = sqlite3.openInMemory();
      drafts = ControllableCorrectionDraftRepository(
        PluginCorrectionDraftRepository.direct(draftDb),
      );
      service.draftRepository = drafts;
      tab = TextBookTab(book: TextBook(title: 'ספר'), index: 0);
      tabId = PluginCorrectionSessionService.tabIdFor(tab);
      ended.clear();
    });

    tearDown(() async {
      drafts.failWrites = false;
      await service.purgeOwner('p');
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      draftDb.close();
      PluginCorrectionSessionService.flushTimeout = const Duration(seconds: 3);
    });

    Future<void> openWindow(WidgetTester tester, {bool failing = false}) async {
      await tester.runAsync(
        () => service.begin(
          owner: 'p',
          tabId: tabId,
          bookId: 'ספר',
          bookUid: 'id:1',
          libraryVersion: 'v1',
          loadSource: (_) async => 'מקור',
          onEvent: (topic, payload) {
            if (topic == 'reader.correctionSessionEnded') {
              ended.add(payload['reason'] as String);
            }
          },
        ),
      );
      drafts.failWrites = failing;
      service.editParagraph(tabId, 0, 'מקור', 'תיקון');
      WindowBus.instance.register();
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: _GuardTabs(tab),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));
    }

    /// מריץ את הסגירה האמיתית עד הדיאלוג (אם יש); ההמשך נשמר ב-[closing].
    late Future<void> closing;
    Future<void> startClose(
      WidgetTester tester,
      AppWindowListener listener,
    ) async {
      closing = listener.handleWindowClose();
      // פעולות המאגר והטיימרים רצים בשעון המדומה; pumpAndSettle לבדו אינו מקדם אותו.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Future<Map<String, Object?>?> stored(WidgetTester tester) => tester
        .runAsync(() => drafts.get('p', correctionDraftId('p', 'id:1')))
        .then((draft) => draft);

    testWidgets('טיוטה שנשמרה: בלי אזהרה, הסשן מסתיים ב-window_closed', (
      tester,
    ) async {
      await openWindow(tester);
      await startClose(tester, AppWindowListener());
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
      await tester.runAsync(() async {
        await closing;
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      expect(runner.closeSelfCalls, 1);
      expect(service.hasSessionForTab(tabId), isFalse);
      expect(ended, ['window_closed']);
      expect(
        ((await stored(tester))!['changes'] as List).single['proposedText'],
        'תיקון',
      );
    });

    testWidgets(
      'כתיבה שנכשלת: ביטול משאיר חלון, סשן ושינוי; אישור סוגר והמצב נשמר '
      'אחרי התאוששות',
      (tester) async {
        await openWindow(tester, failing: true);
        final listener = AppWindowListener();

        await startClose(tester, listener);
        expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => closing);
        expect(runner.closeSelfCalls, 0);
        expect(service.hasSessionForTab(tabId), isTrue);
        expect(service.displayText(tabId, 0, 'מקור'), 'תיקון');

        await startClose(tester, listener);
        await tester.tap(find.text(unsavedChangesCloseAnyway));
        await tester.pumpAndSettle();
        await tester.runAsync(() => closing);
        expect(runner.closeSelfCalls, 1);
        expect(service.hasSessionForTab(tabId), isFalse);
        expect(
          await tester.runAsync(() => service.unsavedStates()),
          hasLength(1),
          reason: 'המצב נשאר באזהרת היציאה עד שיישמר',
        );

        drafts.failWrites = false;
        await tester.runAsync(() async {
          service.retryDraftWrites();
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        });
        expect(
          ((await stored(tester))!['changes'] as List).single['proposedText'],
          'תיקון',
        );
        expect(ended, ['window_closed']);
        // שחרור ה-lease שאחרי ההתאוששות רץ בשעון המדומה.
        await tester.pump(const Duration(milliseconds: 50));
      },
    );
  });

  test('macOS, החלון האחרון: מוסתר, הסשן נשמר, והתהליך אינו מסתיים', () async {
    AppWindowListener.debugKeepsProcessAfterLastWindowOverride = true;
    addTearDown(
      () => AppWindowListener.debugKeepsProcessAfterLastWindowOverride = null,
    );
    runner.windowCount = 1;
    IndexingCrashCanary.start('${tmp.path}/index');
    final canary = IndexingCrashCanary.current!;
    canary.begin('id:active');
    addTearDown(canary.finish);

    var flushed = false;
    Future<void> flush() async => flushed = true;
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    await TabsRepository().saveTabs(const [], 0);

    await AppWindowListener().handleWindowClose();

    expect(flushed, isTrue);
    expect(runner.closeSelfCalls, 1, reason: 'הוסתר במקום כיבוי');
    expect(IndexingCrashCanary.current, same(canary));
    expect(
      await sessions.load(slot),
      isNotNull,
      reason: 'הכרטיסיות של החלון האחרון הן הסשן של הפתיחה הבאה',
    );
  });
}

/// ה-runner המדומה. `windowCount` מחזיר שניים כברירת מחדל — "אינך האחרון".
class _TwoWindowsOpener extends Fake implements WindowOpener {
  @override
  Future<({int count, int max, int engines})?> windowCount() async =>
      (count: 2, max: 8, engines: 1);
}

class _FakeRunner {
  int closeSelfCalls = 0;
  int windowCount = 2;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
          switch (call.method) {
            case 'windowCount':
              return {'count': windowCount, 'max': 4, 'engines': 2};
            case 'closeSelf':
              closeSelfCalls++;
              return null;
            case 'restoreLastClosedWindow':
              return true;
            case 'setBusSlot':
              return null;
            default:
              return null;
          }
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, null);
  }
}

/// החלון הראשון של התהליך — תופס משבצת ואת כינוי המארח, ועונה לכל בקשה.
class _FakeOwner {
  _FakeOwner(this.slot, {this.reply = true});

  final int slot;
  final bool reply;
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.owner',
    );
    _port.listen((message) {
      final map = message as Map;
      if (reply) (map['reply'] as SendPort).send({'ok': true, 'result': null});
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    _port.close();
  }
}

class _GuardTabs extends Fake implements TabsBloc {
  _GuardTabs(this.tab);
  final OpenedTab tab;

  @override
  Stream<TabsState> get stream => const Stream.empty();

  @override
  TabsState get state => TabsState(tabs: [tab], currentTabIndex: 0);
}
