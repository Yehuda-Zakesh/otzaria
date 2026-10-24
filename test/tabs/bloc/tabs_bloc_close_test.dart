import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _Repository extends TabsRepository {
  _Repository({this.restored = const []});
  final List<OpenedTab> restored;
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => restored;
  @override
  int loadCurrentTabIndex() => 0;
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int index) async {}
  @override
  Future<void> flushPendingWrites() async {}
}

void main() {
  setUp(() async => Settings.init(cacheProvider: MemoryCacheProvider()));

  test('פירוק לפני עיבוד LoadTabs משחרר גם את הקוראים המשוחזרים', () async {
    final tab = TextBookTab(book: TextBook(title: 'משוחזר'), index: 0);
    final reader = tab.bloc;
    final tabs = TabsBloc(repository: _Repository(restored: [tab]))
      ..add(LoadTabs());
    await tabs.close();
    await Future<void>.delayed(Duration.zero);
    expect(reader.isClosed, isTrue);
  });

  test('שכפול שכבר בתור מסיים גם פתיחת מלווה לפני הניקוי', () async {
    final source = TextBookTab(book: TextBook(title: 'משנה ברורה'), index: 0);
    final sourceReader = source.bloc;
    final companion = TextBookTab(
      book: TextBook(title: 'ביאור הלכה'),
      index: 0,
    );
    final companionReader = companion.bloc;
    final started = Completer<void>();
    final release = Completer<void>();
    late TextBookTab clone;
    final tabs = TabsBloc(
      repository: _Repository(restored: [source]),
      withCompanion: (tab) async {
        clone = tab as TextBookTab;
        clone.bloc;
        started.complete();
        await release.future;
        return CombinedTab(rightTab: tab, leftTab: companion);
      },
    )..add(LoadTabs());
    await tabs.stream.firstWhere((state) => state.tabs.length == 1);
    tabs.add(CloneTab(source));
    final closing = tabs.close();
    var done = false;
    closing.then((_) => done = true);
    await started.future;
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    final cloneReader = clone.bloc;
    release.complete();
    await closing;
    await Future<void>.delayed(Duration.zero);
    expect(
      [sourceReader, companionReader, cloneReader].every((r) => r.isClosed),
      isTrue,
    );
  });

  test('סגירת כרטיסיה שבתור רשאית לשלוח את אירוע ההסרה שלה', () async {
    final source = TextBookTab(book: TextBook(title: 'פתוח'), index: 0);
    final reader = source.bloc;
    final tabs = TabsBloc(
      repository: _Repository(restored: [source]),
      disposeDelay: Duration.zero,
    )..add(LoadTabs());
    await tabs.stream.firstWhere((state) => state.tabs.length == 1);
    tabs.add(const CloseCurrentTab());
    await tabs.close();
    await Future<void>.delayed(Duration.zero);
    expect(reader.isClosed, isTrue);
  });

  for (final openOrFocus in [false, true]) {
    test(
      'סגירה מנקזת פתיחה לפני שחרור הקוראים: openOrFocus=$openOrFocus',
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
          repository: _Repository(),
          withCompanion: (tab) async {
            started.complete();
            await release.future;
            return CombinedTab(rightTab: tab, leftTab: companion);
          },
        );
        tabs.add(openOrFocus ? OpenOrFocusTab(primary) : AddTab(primary));
        await started.future;
        final closing = tabs.close();
        var done = false;
        closing.then((_) => done = true);
        await Future<void>.delayed(Duration.zero);
        expect(done, isFalse);
        release.complete();
        await closing;
        await Future<void>.delayed(Duration.zero);
        expect(readers.every((reader) => reader.isClosed), isTrue);
        expect(tabs.close(), same(closing));
      },
    );
  }
}
