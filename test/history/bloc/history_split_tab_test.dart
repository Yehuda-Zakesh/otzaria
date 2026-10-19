import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

/// היסטוריה של טאב מפוצל: טאב מפוצל אינו ספר, ולכן בלי פירוק לחלוניות אף
/// מפגש קריאה בפיצול לא היה נרשם — אובדן שקט של "איפה קראתי".
///
/// החלוניות כאן הן טאבי חיפוש: הם היחידים שמייצרים רשומת היסטוריה בלי מסך
/// חי (לספר PDF נדרש `pdfViewerController` מחובר, ולספר טקסט bloc טעון).
class _MemoryHistoryRepository extends HistoryRepository {
  List<Bookmark> stored = [];

  @override
  Future<List<Bookmark>> load() async => stored;

  @override
  Future<List<Bookmark>> mutate(
    List<Bookmark> Function(List<Bookmark> current) apply,
  ) async {
    stored = List<Bookmark>.from(apply(List<Bookmark>.from(stored)));
    return List<Bookmark>.from(stored);
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  SearchingTab search(String query) {
    final tab = SearchingTab(query, query);
    addTearDown(tab.dispose);
    return tab;
  }

  Future<HistoryBloc> loadedBloc(_MemoryHistoryRepository repository) async {
    final bloc = HistoryBloc(repository);
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state is HistoryLoaded);
    return bloc;
  }

  test(
    'AddHistory על טאב מפוצל רושם רשומה לכל חלונית',
    () async {
      final bloc = await loadedBloc(_MemoryHistoryRepository());

      final split = CombinedTab(
        rightTab: search('שאלה א'),
        leftTab: search('שאלה ב'),
      );
      bloc.add(AddHistory(split));
      await bloc.stream.firstWhere((s) => s.history.length == 2);

      // החלונית הראשונה בסדר התצוגה נשארת בראש ההיסטוריה.
      expect(bloc.state.history.map((b) => b.book.title), [
        'שאלה א',
        'שאלה ב',
      ]);
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test('טאב רגיל רושם רשומה אחת', () async {
    final bloc = await loadedBloc(_MemoryHistoryRepository());

    bloc.add(AddHistory(search('יחיד')));
    await bloc.stream.firstWhere((s) => s.history.isNotEmpty);

    expect(bloc.state.history.map((b) => b.book.title), ['יחיד']);
  }, skip: engineReady ? false : searchEngineSkipReason);

  test(
    'AddHistoryForTabs מפרק כל טאב מפוצל שברשימה',
    () async {
      final bloc = await loadedBloc(_MemoryHistoryRepository());

      bloc.add(
        AddHistoryForTabs([
          search('רגיל'),
          CombinedTab(rightTab: search('מפוצל א'), leftTab: search('מפוצל ב')),
        ]),
      );
      await bloc.stream.firstWhere((s) => s.history.length == 3);

      expect(bloc.state.history.map((b) => b.book.title).toSet(), {
        'רגיל',
        'מפוצל א',
        'מפוצל ב',
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'CaptureStateForHistory שומר את כל החלוניות בהשטפה',
    () async {
      final repository = _MemoryHistoryRepository();
      final bloc = await loadedBloc(repository);

      final split = CombinedTab(rightTab: search('א'), leftTab: search('ב'));
      bloc.add(CaptureStateForHistory(split));
      await pumpEventQueue();

      // ה-snapshot ממתין ב-debounce; FlushHistory הוא מה שרץ ביציאה מהמסך.
      bloc.add(FlushHistory());
      await bloc.stream.firstWhere((s) => s.history.length == 2);

      expect(repository.stored, hasLength(2));
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'אותה שאילתה בשתי חלוניות אינה נרשמת פעמיים',
    () async {
      final bloc = await loadedBloc(_MemoryHistoryRepository());

      final split = CombinedTab(
        rightTab: search('אותה שאילתה'),
        leftTab: search('אותה שאילתה'),
      );
      bloc.add(CaptureStateForHistory(split));
      await pumpEventQueue();
      bloc.add(FlushHistory());
      await bloc.stream.firstWhere((s) => s.history.isNotEmpty);

      expect(bloc.state.history, hasLength(1));
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'טאב שאינו מפוצל ממשיך לרשום רשומה אחת',
    () async {
      final bloc = await loadedBloc(_MemoryHistoryRepository());

      bloc.add(AddHistory(search('בודד')));
      await bloc.stream.firstWhere((s) => s.history.isNotEmpty);

      expect(bloc.state.history, hasLength(1));
      expect(bloc.state.history.first.book.title, 'בודד');
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'חלונית עם שאילתה ריקה אינה נרשמת',
    () async {
      final bloc = await loadedBloc(_MemoryHistoryRepository());

      final empty = SearchingTab('ריק', null);
      addTearDown(empty.dispose);
      final split = CombinedTab(rightTab: search('יש'), leftTab: empty);

      bloc.add(AddHistory(split));
      await bloc.stream.firstWhere((s) => s.history.isNotEmpty);
      await pumpEventQueue();

      expect(bloc.state.history, hasLength(1));
      expect(bloc.state.history.first.book.title, 'יש');
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}
