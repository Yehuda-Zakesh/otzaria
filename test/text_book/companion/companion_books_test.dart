import 'package:fake_async/fake_async.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/text_book/companion/companion_book_sync.dart';
import 'package:otzaria/text_book/companion/companion_books.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  TextBookTab textTab(
    String title, {
    BookSource source = BookSource.official,
  }) => TextBookTab(
    book: TextBook(title: title, source: source),
    index: 0,
  );

  group('companion pairs', () {
    test('only Mishnah Berurah has a companion', () {
      expect(companionTitleOf(TextBook(title: 'משנה ברורה')), 'ביאור הלכה');
      expect(companionTitleOf(TextBook(title: 'ביאור הלכה')), isNull);
      expect(companionTitleOf(TextBook(title: 'שער הציון')), isNull);
    });

    test('a personal book with the same title has no companion', () {
      final book = TextBook(
        title: 'משנה ברורה',
        source: BookSource.user,
      );
      expect(companionTitleOf(book), isNull);
    });

    test('finds the pair on either side of a split tab', () {
      final mb = textTab('משנה ברורה');
      final bh = textTab('ביאור הלכה');

      final pair = companionPairOf(CombinedTab(rightTab: bh, leftTab: mb));

      expect(pair?.primary, same(mb));
      expect(pair?.companion, same(bh));
      expect(
        openCompanionPane([CombinedTab(rightTab: mb, leftTab: bh)], mb),
        same(bh),
      );
    });

    test('another book beside Mishnah Berurah is not its companion', () {
      final mb = textTab('משנה ברורה');
      final other = CombinedTab(rightTab: mb, leftTab: textTab('שער הציון'));

      expect(companionPairOf(other), isNull);
      expect(openCompanionPane([other], mb), isNull);
    });
  });

  group('baseLinkNear', () {
    Link source(int line, {int provenance = 0}) => Link(
      heRef: 'שולחן ערוך',
      index1: line + 1,
      path2: 'שולחן ערוך, אורח חיים',
      index2: 10 + line,
      connectionType: LinkTypes.source,
      baseProvenance: provenance,
    );

    test('takes the base link of the line itself', () {
      final link = source(5);
      expect(
        CompanionBookSync.baseLinkNear({
          6: [link],
        }, 5),
        same(link),
      );
    });

    test('looks back past a heading line without links', () {
      final link = source(3);
      expect(
        CompanionBookSync.baseLinkNear({
          4: [link],
        }, 5),
        same(link),
      );
    });

    test('prefers the declared base relation', () {
      final weak = source(5);
      final declared = source(5, provenance: 2);
      expect(
        CompanionBookSync.baseLinkNear({
          6: [weak, declared],
        }, 5),
        same(declared),
      );
    });

    test('ignores commentary links', () {
      final commentary = Link(
        heRef: 'שער הציון',
        index1: 6,
        path2: 'שער הציון',
        index2: 3,
        connectionType: 'commentary',
      );
      expect(
        CompanionBookSync.baseLinkNear({
          6: [commentary],
        }, 5),
        isNull,
      );
    });
  });

  test('the companion follows the primary after the debounce', () {
    fakeAsync((async) {
      final mb = textTab('משנה ברורה');
      final bh = textTab('ביאור הלכה');
      final asked = <int>[];
      final sync = CompanionBookSync(
        primary: mb,
        companion: bh,
        debounce: const Duration(milliseconds: 300),
        resolveCompanionLine: (line) async {
          asked.add(line);
          return line == 40 ? 7 : null;
        },
      );
      async.elapse(const Duration(milliseconds: 400));

      mb.lines.jumpToLine(39);
      async.elapse(const Duration(milliseconds: 100));
      mb.lines.jumpToLine(40);
      async.elapse(const Duration(milliseconds: 400));

      // The intermediate line is skipped, and the companion lands on its line.
      expect(asked, [0, 40]);
      expect(bh.lines.position.value?.topLine, 7);

      sync.dispose();
    });
  });

  group('opening a book', () {
    Future<TabsBloc> openWith(
      OpenedTab tab,
      Future<OpenedTab> Function(OpenedTab) withCompanion,
    ) async {
      final bloc = TabsBloc(
        repository: _FakeTabsRepository(),
        disposeDelay: Duration.zero,
        withCompanion: withCompanion,
      );
      bloc.add(AddTab(tab));
      await bloc.stream.firstWhere((s) => s.tabs.isNotEmpty);
      return bloc;
    }

    test(
      'Mishnah Berurah opens beside Biur Halacha and stays active',
      () async {
        final mb = textTab('משנה ברורה');
        final bh = textTab('ביאור הלכה');
        final bloc = await openWith(
          mb,
          (tab) async => CombinedTab(rightTab: tab, leftTab: bh),
        );

        final combined = bloc.state.tabs.single as CombinedTab;
        expect(combined.rightTab, same(mb));
        expect(combined.leftTab, same(bh));
        expect(bloc.state.activePane, same(mb));

        await bloc.close();
      },
    );

    test('the toggle opens the companion on a third of the width', () async {
      final mb = textTab('משנה ברורה');
      final bloc = await openWith(mb, (tab) async => tab);

      bloc.add(
        OpenTabInSidePane(textTab('ביאור הלכה'), splitRatio: kPrimaryPaneShare),
      );
      await bloc.stream.firstWhere((s) => s.tabs.single is CombinedTab);

      expect((bloc.state.tabs.single as CombinedTab).splitRatio, 2 / 3);

      await bloc.close();
    });

    test('a book without a companion opens alone', () async {
      final other = textTab('שער הציון');
      final bloc = await openWith(other, withCompanionPane);

      expect(bloc.state.tabs.single, same(other));

      await bloc.close();
    });

    test(
      'Mishnah Berurah opens alone after the user hid the companion',
      () async {
        await setShowCompanionBookByDefault(false);
        final mb = textTab('משנה ברורה');
        final bloc = await openWith(mb, withCompanionPane);

        expect(bloc.state.tabs.single, same(mb));

        await bloc.close();
      },
    );
  });
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs() => [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
}
