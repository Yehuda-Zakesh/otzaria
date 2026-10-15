import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// החיפוש בספר שומר את החלופות המנורמלות של החיפוש הקודם, ופותח איתן שוב את
/// הדיאלוג המתקדם — שם הן נערכות.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets(
    'חלופה נוספת למילה שכבר יש לה חלופה מחיפוש קודם (issue #1734)',
    (tester) async {
      final previous = SearchQueryBuilder.normalizeParametersForMode(
        SearchMode.advanced,
        customSpacing: {'שלום_0': '2'},
        alternativeWords: {
          0: ['שלם'],
        },
        searchOptions: {
          'שלום_0': {'קידומות': true},
        },
      );
      final tab = SearchingTab(
        'חיפוש',
        'שלום עולם',
        initialConfiguration: SearchConfiguration.forInBookSearch(
          searchMode: SearchMode.advanced,
          distance: 2,
          matchPolicy: SearchMatchPolicy.standard,
        ),
      );
      addTearDown(tab.dispose);
      tab.copyWordSettingsFrom(
        searchOptions: previous.searchOptions,
        alternativeWords: previous.alternativeWords,
        spacingValues: previous.customSpacing,
      );
      tab.useGlobalSearchOptions.value = false;
      tab.queryController.selection = const TextSelection.collapsed(
        offset: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 900, child: AdvancedSearchControls(tab: tab)),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(_alternativeFieldFinder, 'שולם');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tab.alternativeWords[0], ['שלם', 'שולם']);
      // עריכה בדיאלוג אינה משנה את הגדרות המסך — גם אם הדיאלוג יבוטל.
      expect(previous.alternativeWords[0], ['שלם']);
      final remove = find.descendant(
        of: find.widgetWithText(ListTile, 'שלם'),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tab.alternativeWords[0], ['שולם']);
      expect(previous.alternativeWords[0], ['שלם']);
      tab.spacingValues['שלום_0'] = '9';
      expect(previous.customSpacing, {'שלום_0': '2'});
      tab.searchOptions['שלום_0']!['סיומות'] = true;
      expect(previous.searchOptions['שלום_0'], {'קידומות': true});
    },
    skip: !engineReady,
  );
}

final _alternativeFieldFinder = find.byWidgetPredicate(
  (widget) =>
      widget is RtlTextField && widget.decoration?.labelText == 'מילה חילופית',
);
