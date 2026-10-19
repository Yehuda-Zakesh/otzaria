import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../helpers/memory_settings_cache.dart';

TextBookTab _book(String title) =>
    TextBookTab(book: TextBook(title: title), index: 0);

ToolTab _tool(String id) => ToolTab(toolId: id, title: id);

TabsState _state({
  required List<OpenedTab> tabs,
  int index = 0,
  OpenedTab? activePane,
}) =>
    TabsState(
      tabs: const [],
      currentTabIndex: 0,
    ).copyWith(
      tabs: tabs,
      currentTabIndex: index,
      activePane: activePane == null
          ? const ActivePaneUpdate.unchanged()
          : ActivePaneUpdate.set(activePane),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // רגרסיה: לפני שהכלים עברו לכרטיסיות, מסך הכלים היה נפרד ולכן activePane
  // תמיד הצביע על ספר. תוסף שנפתח מתפריט ההקשר של ספר חייב להמשיך לקרוא את
  // מיקום הספר — אחרת reader.getSelection/getCurrentRef מחזירים ריק.
  group('TabsState.readingPane', () {
    test('כרטיסיית ספר — readingPane הוא הספר עצמו', () {
      final book = _book('בראשית');
      final state = _state(tabs: [book]);
      expect(state.readingPane, same(book));
    });

    test('מעבר לכרטיסיית כלי משמר את הספר כ-readingPane', () {
      final book = _book('בראשית');
      final tool = _tool('builtin.calendar');
      var state = _state(tabs: [book, tool], index: 0);
      expect(state.readingPane, same(book));

      state = state.copyWith(currentTabIndex: 1);
      expect(state.activePane, same(tool));
      expect(
        state.readingPane,
        same(book),
        reason: 'טאב כלי אינו מקום קריאה ואינו מאפס את ההקשר',
      );
    });

    test('טאב מפוצל של כלי וספר — הספר שבאותו טאב מנצח', () {
      final bookA = _book('בראשית');
      final bookB = _book('שמות');
      final tool = _tool('builtin.gematria');
      final split = CombinedTab(rightTab: tool, leftTab: bookB);

      var state = _state(tabs: [bookA, split], index: 0);
      expect(state.readingPane, same(bookA));

      // עוברים לטאב המפוצל והחלונית הפעילה היא הכלי.
      state = state.copyWith(
        currentTabIndex: 1,
        activePane: ActivePaneUpdate.set(tool),
      );
      expect(state.activePane, same(tool));
      expect(
        state.readingPane,
        same(bookB),
        reason: 'הספר שבאותו טאב עדיף על ספר מטאב אחר',
      );
    });

    test('סגירת ספר הקריאה מנקה את הזיכרון ואינו מחזיר טאב סגור', () {
      final book = _book('בראשית');
      final tool = _tool('builtin.calendar');
      var state = _state(tabs: [book, tool], index: 0);
      expect(state.readingPane, same(book));

      state = state.copyWith(currentTabIndex: 1);
      expect(state.readingPane, same(book));

      // הספר נסגר — ה-readingPane חייב להתאפס ולא להצביע על טאב שאינו פתוח.
      state = state.copyWith(tabs: [tool], currentTabIndex: 0);
      expect(state.readingPane, isNull);
    });

    test('כרטיסיית כלי בלבד — אין readingPane', () {
      final state = _state(tabs: [_tool('builtin.notes')]);
      expect(state.readingPane, isNull);
    });

    test('חזרה לספר מחזירה אותו כ-readingPane', () {
      final book = _book('בראשית');
      final tool = _tool('builtin.calendar');
      var state = _state(tabs: [book, tool], index: 1);
      expect(state.readingPane, isNull, reason: 'מעולם לא היה ספר פעיל');

      state = state.copyWith(currentTabIndex: 0);
      expect(state.readingPane, same(book));
    });
  });

  group('ToolTab.visiblePluginInstancesOf', () {
    test('כרטיסיית תוסף בודדת', () {
      final tool = _tool('com.example.plugin');
      expect(ToolTab.visiblePluginInstancesOf(tool), {
        (pluginId: 'com.example.plugin', instanceId: tool.instanceId),
      });
    });

    test('כלי מובנה אינו תוסף ואינו נכנס לקבוצה', () {
      expect(
        ToolTab.visiblePluginInstancesOf(_tool('builtin.calendar')),
        isEmpty,
      );
    });

    test('כרטיסיית ספר — קבוצה ריקה', () {
      expect(ToolTab.visiblePluginInstancesOf(_book('בראשית')), isEmpty);
    });

    test('טאב מפוצל מחזיר את מופעי התוספים שבשתי החלוניות', () {
      final a = _tool('com.a');
      final b = _tool('com.b');
      final split = CombinedTab(rightTab: a, leftTab: b);
      expect(ToolTab.visiblePluginInstancesOf(split), {
        (pluginId: 'com.a', instanceId: a.instanceId),
        (pluginId: 'com.b', instanceId: b.instanceId),
      });
    });

    test('חלונית ספר בטאב מפוצל אינה מוסיפה תוסף', () {
      final a = _tool('com.a');
      final split = CombinedTab(rightTab: a, leftTab: _book('בראשית'));
      expect(ToolTab.visiblePluginInstancesOf(split), {
        (pluginId: 'com.a', instanceId: a.instanceId),
      });
    });

    test('שני מופעים של אותו תוסף בטאב מפוצל — שני מפתחות נפרדים', () {
      final a1 = _tool('com.a');
      final a2 = _tool('com.a');
      final split = CombinedTab(rightTab: a1, leftTab: a2);
      expect(ToolTab.visiblePluginInstancesOf(split), hasLength(2));
    });

    test('null — קבוצה ריקה', () {
      expect(ToolTab.visiblePluginInstancesOf(null), isEmpty);
    });
  });
}
