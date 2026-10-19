import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

import '../../helpers/memory_settings_cache.dart';
import '../../support/search_engine_test_init.dart';

/// הכרטיסיה הפעילה נלכדת בסגירה. בלי זה הספר שנקרא עכשיו לא נרשם כלל:
/// הלכידה שבפתיחתו רצה לפני שה-bloc שלו נטען ומחזירה null, ואחריה אין
/// לכידה נוספת כל עוד הוא נשאר הכרטיסיה הפעילה.
///
/// הכרטיסיה כאן היא טאב חיפוש — היחיד שמייצר רשומת היסטוריה בלי מסך חי.
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

  Future<HistoryBloc> loadedBloc(
    _MemoryHistoryRepository repository,
    OpenedTab? Function() currentTab,
  ) async {
    final bloc = HistoryBloc(repository, currentTab: currentTab);
    addTearDown(bloc.close);
    await bloc.stream.firstWhere((state) => state is HistoryLoaded);
    return bloc;
  }

  test(
    'סגירת התוכנה רושמת את הכרטיסיה הפעילה שלא נלכדה',
    () async {
      final repository = _MemoryHistoryRepository();
      final current = search('הכרטיסיה הפעילה');
      await loadedBloc(repository, () => current);

      // אף לכידה לא הצליחה עד כה — בדיוק המצב של ספר שנפתח ונשאר פעיל.
      expect(repository.stored, isEmpty);

      await PreCloseRegistry.runAll();

      expect(repository.stored.map((b) => b.book.title), [
        'הכרטיסיה הפעילה',
      ]);
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'FlushHistory לוכד את הכרטיסיה הפעילה יחד עם הממתינים',
    () async {
      final repository = _MemoryHistoryRepository();
      final current = search('הפעילה');
      final bloc = await loadedBloc(repository, () => current);

      bloc.add(CaptureStateForHistory(search('קודמת')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bloc.add(FlushHistory());
      await bloc.stream.firstWhere((s) => s.history.length == 2);

      expect(
        bloc.state.history.map((b) => b.book.title),
        containsAll(['הפעילה', 'קודמת']),
      );
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  test(
    'בלי ספק לכרטיסיה הפעילה הסגירה אינה כותבת דבר',
    () async {
      final repository = _MemoryHistoryRepository();
      final bloc = HistoryBloc(repository);
      addTearDown(bloc.close);
      await bloc.stream.firstWhere((state) => state is HistoryLoaded);

      await PreCloseRegistry.runAll();

      expect(repository.stored, isEmpty);
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}
