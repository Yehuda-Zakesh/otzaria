import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

ToolTab _tab(String title) => ToolTab(toolId: 'builtin.calendar', title: title);

/// שני חלונות באותו isolate: כל אחד עם [WindowTabsSession] משלו.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  TabsRepository repoFor(WindowTabsSession window) =>
      TabsRepository(sessions: sessions, window: window);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_window_tabs_session_');
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
  });

  tearDown(() {
    database.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final tabs = [_tab('א'), _tab('ב'), _tab('ג')];

  test('ברירת המחדל היא החלון של ה-isolate הזה', () {
    expect(TabsRepository().window, same(WindowTabsSession.current));
    expect(
      TabsRepository.sessionGeneration,
      WindowTabsSession.current.generation,
    );
  });

  test('שני חלונות כותבים כל אחד לשורה שלו', () async {
    final first = repoFor(WindowTabsSession(slot: () => 1));
    final second = repoFor(WindowTabsSession(slot: () => 2));

    await first.saveTabs([_tab('של הראשון')], 0);
    await second.saveTabs([_tab('של השני')], 0);

    expect((await sessions.load(1))!.tabsJson, contains('של הראשון'));
    expect((await sessions.load(1))!.tabsJson, isNot(contains('של השני')));
    expect((await sessions.load(2))!.tabsJson, contains('של השני'));
    expect(first.loadTabs().single.title, 'של הראשון');
    expect(second.loadTabs().single.title, 'של השני');
  });

  test('כתיבת האינדקס המושהית של חלון אחד אינה נוגעת בשני', () async {
    final first = repoFor(WindowTabsSession(slot: () => 1));
    final second = repoFor(WindowTabsSession(slot: () => 2));
    await first.saveTabs(tabs, 0);
    await second.saveTabs(tabs, 0);

    await first.saveCurrentTabIndex(tabs, 1);
    await second.saveCurrentTabIndex(tabs, 2);
    // ה-flush של השני כותב רק את שלו, ואינו מבטל את הממתינה של הראשון.
    await second.flushPendingWrites();
    expect((await sessions.load(2))!.currentIndex, 2);
    expect((await sessions.load(1))!.currentIndex, 0);

    await first.flushPendingWrites();
    expect((await sessions.load(1))!.currentIndex, 1);
    expect((await sessions.load(2))!.currentIndex, 2);
  });

  test('סגירת חלון אחד אינה מבטלת כתיבה ממתינה של אחר', () async {
    final first = repoFor(WindowTabsSession(slot: () => 1));
    final second = repoFor(WindowTabsSession(slot: () => 2));
    await first.saveTabs(tabs, 0);
    await second.saveTabs(tabs, 0);

    await first.saveCurrentTabIndex(tabs, 2);
    await second.saveTabs(tabs, 1);
    await second.discardWindowSession();

    expect(await sessions.load(2), isNull);
    await first.flushPendingWrites();
    expect((await sessions.load(1))!.currentIndex, 2);
  });

  test('ההשהיה עצמה כותבת לשורה של החלון שלה', () async {
    final first = repoFor(WindowTabsSession(slot: () => 1));
    final second = repoFor(WindowTabsSession(slot: () => 2));
    await first.saveTabs(tabs, 0);
    await second.saveTabs(tabs, 0);

    await first.saveCurrentTabIndex(tabs, 1);
    await second.saveCurrentTabIndex(tabs, 2);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect((await sessions.load(1))!.currentIndex, 1);
    expect((await sessions.load(2))!.currentIndex, 2);
  });

  test('מאגרים של אותו חלון חולקים את הכתיבה הממתינה', () async {
    final window = WindowTabsSession(slot: () => 1);
    final blocRepo = repoFor(window);
    await blocRepo.saveTabs(tabs, 0);
    await blocRepo.saveCurrentTabIndex(tabs, 2);

    // כמו בסגירת חלון: מאגר אחר של אותו חלון מוחק ומבטל את הממתינה.
    await repoFor(window).discardWindowSession();
    await blocRepo.flushPendingWrites();

    expect(await sessions.load(1), isNull);
  });

  test('ייבוא מקדם רק את הדור של החלון שלו', () async {
    final first = WindowTabsSession(slot: () => 1);
    final second = WindowTabsSession(slot: () => 2);

    await repoFor(first).importRaw({'tabs': <dynamic>[], 'currentTab': 0});

    expect(first.generation, 1);
    expect(second.generation, 0);
  });

  test('bloc שנבנה לפני ייבוא בחלון שלו מפסיק לשמור', () async {
    TabsBloc blocFor(WindowTabsSession window) {
      final bloc = TabsBloc(
        repository: repoFor(window),
        session: window,
        disposeDelay: Duration.zero,
      );
      addTearDown(bloc.close);
      return bloc;
    }

    final imported = WindowTabsSession(slot: () => 1);
    final other = WindowTabsSession(slot: () => 2);
    final importedBloc = blocFor(imported);
    final otherBloc = blocFor(other);

    await repoFor(imported).importRaw({'tabs': <dynamic>[], 'currentTab': 0});
    importedBloc.add(AddTab(_tab('אחרי הייבוא')));
    otherBloc.add(AddTab(_tab('אחרי הייבוא')));
    // החלון השני עדיין שומר — סימן שהשמירה של הראשון הייתה מגיעה עד עכשיו.
    for (var i = 0; i < 100; i++) {
      final saved = await sessions.load(2);
      if (saved != null && saved.tabsJson.contains('אחרי')) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect((await sessions.load(2))!.tabsJson, contains('אחרי'));
    expect((await sessions.load(1))!.tabsJson, isNot(contains('אחרי')));
  });

  test('חלון בלי משבצת אינו כותב', () async {
    final orphan = repoFor(WindowTabsSession(slot: () => null));
    final first = repoFor(WindowTabsSession(slot: () => 1));
    await first.saveTabs([_tab('של הראשון')], 0);

    await orphan.saveTabs([_tab('לא אמור להישמר')], 0);
    await orphan.saveCurrentTabIndex(tabs, 2);
    await orphan.flushPendingWrites();

    expect(await sessions.loadAll(), hasLength(1));
    expect((await sessions.load(1))!.tabsJson, contains('של הראשון'));
  });
}
