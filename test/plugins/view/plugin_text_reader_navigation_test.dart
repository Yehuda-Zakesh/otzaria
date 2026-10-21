import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/view/plugin_text_reader.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import '../services/plugin_text_reader_registry_test.dart' as fixture;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';
import '../../test_helpers/reading_toc.dart';

class _FakeTabsBloc extends Mock implements TabsBloc {
  @override
  Stream<TabsState> get stream => const Stream.empty();
  @override
  TabsState get state => const TabsState(tabs: [], currentTabIndex: 0);
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemoryCacheProvider()));
  testWidgets(
    'search navigation after enabling embedded reader skips the detached list',
    (tester) async {
      final lines = LineScrollController();
      addTearDown(lines.dispose);
      var jumps = 0;
      lines.addBeforeJumpListener(() => jumps++);
      final segments = buildReadingSegments(
        List.filled(30, 'טקסט'),
        continuous: false,
      );
      final binding = ReadingViewportBinding(
        segments: () => segments,
        viewportExtent: () => 600,
      );
      lines.attach(binding);
      await tester.pumpWidget(
        MaterialApp(
          home: ScrollablePositionedList.builder(
            itemScrollController: lines.itemController,
            scrollOffsetController: lines.offsetController,
            itemPositionsListener: lines.positionsListener,
            itemCount: 30,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      lines.detach(binding);
      final targets = <int>[];
      lines.externalNavigator = (line) async => targets.add(line);
      await lines.scrollToLine(2, alignment: 0.35);
      expect(targets, [2]);
      expect(jumps, 1);
    },
  );
  testWidgets('embedded continuous reader receives requested source line', (
    tester,
  ) async {
    final book = TextBook(title: 'ברכות');
    final tab = TextBookTab(book: book, index: 0);
    tab.bloc.emit(
      TextBookLoaded.initial(
        book: book,
        index: 0,
        showLeftPane: false,
        splitView: false,
      ).copyWith(
        content: const ['שורה ראשונה', 'שורה שנייה', 'שורה שלישית'],
        continuousReadingMode: true,
      ),
    );
    final segments = readingSegmentsOf(tab.bloc.state as TextBookLoaded);
    expect(segments, hasLength(1));
    await PluginTextReaderRegistry.instance.select(fixture.plugin(), false);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: _FakeTabsBloc()),
          BlocProvider<TextBookBloc>.value(value: tab.bloc),
        ],
        child: MaterialApp(
          home: PluginTextReader(tab: tab, nativeReader: const SizedBox()),
        ),
      ),
    );
    await PluginTextReaderRegistry.instance.select(fixture.plugin(), true);
    await tab.lines.scrollToLine(2);
    expect(tab.index, 2);
    await PluginTextReaderRegistry.instance.select(fixture.plugin(), false);
    await tester.pumpWidget(const SizedBox());
    tab.dispose();
  });
  test('reader navigation payload carries currently active search', () {
    final book = TextBook(title: 'ברכות');
    final tab = TextBookTab(book: book, index: 0, searchText: 'החיפוש הקודם');
    tab.bloc.emit(
      TextBookLoaded.initial(
        book: book,
        index: 0,
        showLeftPane: false,
        splitView: false,
      ).copyWith(searchText: 'המילה החדשה'),
    );
    final payload = PluginTextReaderRegistry.bookPayload(tab);
    expect(payload['searchQuery'], 'המילה החדשה');
    tab.bloc.emit((tab.bloc.state as TextBookLoaded).copyWith(searchText: ''));
    expect(PluginTextReaderRegistry.bookPayload(tab)['searchQuery'], '');
    tab.dispose();
  });
}
