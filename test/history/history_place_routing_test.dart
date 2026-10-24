import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../helpers/memory_settings_cache.dart';

class _MemoryTabs extends TabsRepository {
  _MemoryTabs([this.tabs = const []]);
  List<OpenedTab> tabs;

  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => tabs;
  @override
  int loadCurrentTabIndex() => 0;
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {
    this.tabs = tabs;
  }

  @override
  Future<void> saveCurrentTabIndex(List<OpenedTab> tabs, int index) async {}
  @override
  Future<void> flushPendingWrites() async {}
}

PdfBookTab _pdf(
  int page, {
  String? slot,
  String path = '/a.pdf',
  String query = '',
}) => PdfBookTab(
  book: PdfBook(title: 'ספר', path: path),
  pageNumber: page,
  searchText: query,
)..historySlot = slot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  late TabsBloc bloc;
  setUp(() => bloc = TabsBloc(repository: _MemoryTabs()));
  tearDown(() => bloc.close());

  Future<void> send(TabsEvent event) async {
    bloc.add(event);
    await pumpEventQueue();
  }

  test('היסטוריה: שני מקומות תחת אותה כותרת אינם ממוחזרים זה בזה', () async {
    final first = _pdf(10, slot: 'a')..currentTitle.value = 'פרק א';
    await send(AddTab(first));
    final incoming = _pdf(50, slot: 'b')..currentTitle.value = 'פרק א';
    await send(
      OpenOrFocusTab(incoming, targetTitle: 'פרק א', matchHistorySlot: true),
    );
    expect(bloc.state.tabs, [first, incoming]);
    expect(bloc.state.currentTab, same(incoming));
    expect(first.pageNumber, 10);
    expect(incoming.pageNumber, 50);
    expect(incoming.historySlot, 'b');
  });

  test('היסטוריה: מקום שכבר פתוח ממוקד גם לאחר שהתקדם לכותרת אחרת', () async {
    final a = _pdf(10, slot: 'a');
    final b = _pdf(80, slot: 'b')..currentTitle.value = 'פרק ב';
    await send(AddTab(a));
    await send(AddTab(b));
    await send(SetCurrentTab(0));
    await send(
      OpenOrFocusTab(
        _pdf(50, slot: 'b'),
        targetTitle: 'פרק א',
        matchHistorySlot: true,
      ),
    );
    expect(bloc.state.tabs, [a, b]);
    expect(bloc.state.currentTab, same(b));
    expect(b.pageNumber, 80);
  });

  test('היסטוריה ישנה ללא slot ממקדת רק את המקום ללא slot', () async {
    final slotted = _pdf(80, slot: 'b');
    final legacy = _pdf(10);
    await send(AddTab(slotted));
    await send(AddTab(legacy));
    await send(SetCurrentTab(0));
    await send(OpenOrFocusTab(_pdf(10), matchHistorySlot: true));
    expect(bloc.state.currentTab, same(legacy));
    expect(bloc.state.tabs, hasLength(2));
  });

  test(
    'רשומת legacy אינה ממקדת שרירותית את הטאב הראשון לאחר מיגרציה',
    () async {
      final first = _pdf(10)..currentTitle.value = 'פרק א';
      final lastRead = _pdf(50)..currentTitle.value = 'פרק ב';
      await bloc.close();
      bloc = TabsBloc(repository: _MemoryTabs([first, lastRead]));
      await send(LoadTabs());
      final incoming = _pdf(50)..currentTitle.value = 'פרק ב';
      await send(
        OpenOrFocusTab(incoming, targetTitle: 'פרק ב', matchHistorySlot: true),
      );
      expect((bloc.state.currentTab as PdfBookTab).pageNumber, 50);
      expect(bloc.state.currentTab, isNot(same(first)));
      expect(first.pageNumber, 10);
      expect(lastRead.pageNumber, 50);
    },
  );

  test(
    'מקום null חדש ממוקד לפי slot גם לאחר סידור טאבים תחת אותה כותרת',
    () async {
      final first = _pdf(10)..currentTitle.value = 'פרק א';
      final other = _pdf(50, slot: 'b')..currentTitle.value = 'פרק א';
      await send(AddTab(first));
      await send(AddTab(other));
      await send(MoveTab(other, 0));
      await send(
        OpenOrFocusTab(_pdf(10), targetTitle: 'פרק א', matchHistorySlot: true),
      );
      expect(bloc.state.currentTab, same(first));
      expect(bloc.state.tabs, [other, first]);
    },
  );

  test('אותו slot בספר שונה אינו ממקד ספר אחר', () async {
    final first = _pdf(10, slot: 'a');
    await send(AddTab(first));
    final incoming = _pdf(50, slot: 'a', path: '/b.pdf');
    await send(OpenOrFocusTab(incoming, matchHistorySlot: true));
    expect(bloc.state.tabs, [first, incoming]);
    expect(incoming.historySlot, 'a');
  });

  test('סימנייה ו-deep link ממשיכים לנווט בטאב קיים ללא התאמת slot', () async {
    final first = _pdf(10, slot: 'a');
    await send(AddTab(first));
    await send(
      OpenOrFocusTab(_pdf(50, slot: 'b'), navigateToPositionIfReused: true),
    );
    expect(bloc.state.tabs, [first]);
    expect(first.pageNumber, 50);
    expect(first.historySlot, 'a');
  });

  test('חיפוש רגיל תחת אותה כותרת ממשיך למחזר טאב גם כשה-slot שונה', () async {
    final first = _pdf(10, slot: 'a')..currentTitle.value = 'פרק א';
    await send(AddTab(first));
    await send(
      OpenOrFocusTab(
        _pdf(50, slot: 'b', query: 'מילה'),
        targetTitle: 'פרק א',
      ),
    );
    expect(bloc.state.tabs, [first]);
    expect(first.searchText, 'מילה');
    expect(first.pageNumber, 10);
  });

  test(
    'שני מקומות בטאב מפוצל: מיקוד, ניווט וחיפוש מגיעים לאותה חלונית',
    () async {
      final a = _pdf(10, slot: 'a');
      final b = _pdf(50, slot: 'b');
      final combined = CombinedTab(rightTab: a, leftTab: b);
      await send(AddTab(combined));
      await send(
        OpenOrFocusTab(
          _pdf(70, slot: 'b', query: 'יעד'),
          matchHistorySlot: true,
          navigateToPositionIfReused: true,
        ),
      );
      expect(bloc.state.tabs, [combined]);
      expect(bloc.state.activePane, same(b));
      expect(a.pageNumber, 10);
      expect(a.searchText, isEmpty);
      expect(b.pageNumber, 70);
      expect(b.searchText, 'יעד');
    },
  );

  test('מקום בטקסט ממוקד לפי slot בלי לטעון תוכן עניינים או BLoC', () async {
    final previousObserver = Bloc.observer;
    final counter = _TextBookBlocCounter();
    Bloc.observer = counter;
    final previousResolver = TextBookTab.locationTitleResolver;
    TextBookTab.locationTitleResolver = (_, _) =>
        throw StateError('unexpected title lookup');
    addTearDown(() {
      Bloc.observer = previousObserver;
      TextBookTab.locationTitleResolver = previousResolver;
    });
    final book = TextBook(id: 7, title: 'ספר');
    final a = TextBookTab(book: book, index: 10)..historySlot = 'a';
    final b = TextBookTab(book: book, index: 50)..historySlot = 'b';
    await send(AddTab(a));
    await send(AddTab(b));
    await send(SetCurrentTab(0));
    await send(
      OpenOrFocusTab(
        TextBookTab(book: book, index: 50)..historySlot = 'b',
        matchHistorySlot: true,
      ),
    );
    expect(bloc.state.currentTab, same(b));
    expect(counter.created, 0);
  });

  for (final load in [true, false]) {
    test(
      load
          ? 'טעינה מפרידה 100 טאבים ישנים ושומרת slots ייחודיים'
          : 'החלפת שולחן משמרת 101 זהויות קריאה שנשמרו',
      () async {
        final tabs = List<OpenedTab>.generate(
          100,
          (i) => _pdf(i + 1, slot: load || i == 0 ? null : 'stored-$i'),
        );
        final existing = _pdf(201, slot: 'kept');
        tabs.add(existing);
        if (load) {
          await bloc.close();
          bloc = TabsBloc(repository: _MemoryTabs(tabs));
          await send(LoadTabs());
        } else {
          await send(ReplaceAllTabs(tabs, 0));
        }
        final slots = bloc.state.tabs.map((t) => t.historySlot).toList();
        expect(slots.toSet(), hasLength(101));
        expect(slots.first, isNull);
        expect(existing.historySlot, 'kept');
        final copies = bloc.state.tabs.map(OpenedTab.from).toList();
        await send(ReplaceAllTabs(copies, 0));
        expect(bloc.state.tabs.map((t) => t.historySlot), slots);
      },
    );
  }

  test('החלפת מחזיק מקום בספר שכבר פתוח מפרידה את ההיסטוריה', () async {
    final first = _pdf(10, slot: 'a');
    await send(AddTab(first));
    final placeholder = ResolvingTab(
      fallbackTab: _pdf(50),
      resolve: () async => _pdf(50),
    );
    await send(AddTab(placeholder));
    final resolved = _pdf(50, slot: 'a');
    await send(ReplaceTab(oldTab: placeholder, newTab: resolved));
    expect(bloc.state.tabs, [first, resolved]);
    expect(resolved.historySlot, isNot('a'));
  });

  test('החלפת טאב באותו מקום אינה מחליפה את ה-slot שלו', () async {
    final original = _pdf(10, slot: 'a');
    await send(AddTab(original));
    final replacement = _pdf(50, slot: 'a');
    await send(ReplaceTab(oldTab: original, newTab: replacement));
    expect(replacement.historySlot, 'a');
  });

  test('אימוץ טאב מחלון אחר מפריד מול מוצמד שנשאר', () async {
    final pinned = _pdf(10, slot: 'a')..isPinned = true;
    await send(AddTab(pinned));
    final transferred = _pdf(50, slot: 'a');
    await send(AdoptTab(transferred));
    expect(bloc.state.tabs, [pinned, transferred]);
    expect(transferred.historySlot, isNot('a'));
  });

  test('אימוץ טאב משמר את זהותו כשאין התנגשות בחלון היעד', () async {
    await send(AddTab(_pdf(10, slot: 'a')));
    final transferred = _pdf(50, slot: 'a');
    await send(AdoptTab(transferred));
    expect(bloc.state.tabs, [transferred]);
    expect(transferred.historySlot, 'a');
  });

  test('הזזה, שילוב ופירוק משמרים את מקומות הקריאה', () async {
    final a = _pdf(10, slot: 'a');
    final b = _pdf(50, slot: 'b');
    await send(AddTab(a));
    await send(AddTab(b));
    await send(MoveTab(b, 0));
    await send(CreateCombinedTab(rightTab: a, leftTab: b));
    expect(bloc.state.tabs, hasLength(1));
    await send(const ExpandCombinedTab(0));
    expect(bloc.state.tabs.toSet(), {a, b});
    expect(a.historySlot, 'a');
    expect(b.historySlot, 'b');
  });

  test('JSON ושכפול של טאב מפוצל משמרים את ה-slots של שתי החלוניות', () {
    final combined = CombinedTab(
      rightTab: _pdf(10, slot: 'a'),
      leftTab: _pdf(50, slot: 'b'),
    );
    addTearDown(combined.dispose);
    for (final copy in [
      combined.clone(),
      OpenedTab.fromJson(combined.toJson()),
      RunnerWindowChannel.transferRoundTrip(combined)!,
    ]) {
      addTearDown(copy.dispose);
      expect(leafPanes(copy).map((p) => p.historySlot), ['a', 'b']);
    }
  });
}

class _TextBookBlocCounter extends BlocObserver {
  int created = 0;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (bloc is TextBookBloc) created++;
  }
}
