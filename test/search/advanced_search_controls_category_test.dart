import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  // הווידג'ט קורא ל-splitQueryWords שמאציל למנוע ה-Rust; ב-CI שלא בונה
  // את הספרייה הנייטיבית הבדיקה מדולגת כמו יתר בדיקות החיפוש התלויות בה.
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('אפשרויות פר-מילה מתעלמות מחלק @קטגוריה', (tester) async {
    final tab = SearchingTab('חיפוש', 'שלום @תורה');
    tab.useGlobalSearchOptions.value = false;
    tab.queryController.selection = const TextSelection.collapsed(offset: 9);
    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: AdvancedSearchControls(
              tab: tab,
              supportsCategorySyntax: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('בחר מילה'), findsOneWidget);
    expect(_alternativeFieldFinder, findsNothing);

    tab.queryController.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    expect(find.text('שלום'), findsOneWidget);
    expect(
      tester.widget<RtlTextField>(_alternativeFieldFinder).enabled,
      isTrue,
    );
  }, skip: !engineReady);
}

final _alternativeFieldFinder = find.byWidgetPredicate(
  (widget) =>
      widget is RtlTextField && widget.decoration?.labelText == 'מילה חילופית',
);
