import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/utils/pdf_plugin_menu_entries.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  final book = PdfBook(title: 'ברכות', path: r'C:\ספרים\ברכות.pdf', id: 9);

  const save = {
    'type': 'storage.set',
    'args': {
      'key': 'last',
      'value': {r'$selection': 'selectedText'},
    },
  };

  const items = [
    ('legacy', PluginContextMenuItem(id: 'legacy', label: 'על הטקסט')),
    (
      'plugin',
      PluginContextMenuItem(
        id: 'search',
        label: 'חפש',
        contexts: ['reader-pdf-selection'],
        action: save,
      ),
    ),
    (
      'plugin',
      PluginContextMenuItem(
        id: 'page',
        label: 'פעולה על העמוד',
        contexts: ['reader-pdf'],
        action: save,
      ),
    ),
  ];

  test('מספר העמוד נמסר כ-pageNumber ובמקום sectionIndex', () {
    final payload = buildPdfPluginPayload(
      book: book,
      pageNumber: 12,
      currentRef: 'פרק א',
      selectedText: 'מאימתי',
    );
    expect(payload['id'], 9);
    expect(payload['type'], 'pdf');
    expect(payload['bookId'], 'ברכות');
    expect(payload['currentBook'], 'ברכות');
    expect(payload['bookUid'], isNotEmpty);
    expect(payload['pageNumber'], 12);
    expect(payload['sectionIndex'], 12);
    expect(payload['currentIndex'], 12);
    expect(payload['currentRef'], 'פרק א');
    expect(payload['text'], 'מאימתי');
  });

  test('בלי תוכן עניינים הכתובת היא מספר העמוד', () {
    final tab = PdfBookTab(book: book, pageNumber: 1);
    addTearDown(tab.dispose);
    expect(pdfPageRef(tab, 7), 'עמוד 7');
  });

  group('buildPdfPluginMenuEntries', () {
    Future<List<AppContextMenuEntry>> entries(
      WidgetTester tester, {
      bool hasSelection = false,
      String? loadedText,
      Future<String> Function()? readSelectedText,
      bool copyAllowed = true,
      List<Map<String, dynamic>>? clicks,
      List<(String, PluginContextMenuItem)> records = items,
    }) async {
      await tester.pumpWidget(const SizedBox());
      return buildPdfPluginMenuEntries(
        book: book,
        pageNumber: 3,
        currentRef: 'עמוד 3',
        hasSelection: hasSelection,
        loadedText: loadedText,
        readSelectedText: readSelectedText ?? () async => 'נקרא בלחיצה',
        copyAllowed: copyAllowed,
        menuContext: tester.element(find.byType(SizedBox)),
        records: records,
        selectionActionDispatcher: (pluginId, action, payload) async =>
            clicks?.add(payload),
      );
    }

    List<String> labels(List<AppContextMenuEntry> entries) => [
      for (final e in entries) e.isDivider ? '---' : e.label!,
    ];

    Future<void> click(WidgetTester tester, AppContextMenuEntry entry) =>
        tester.runAsync(() async {
          entry.onTap!();
          await Future<void>.delayed(Duration.zero);
        });

    testWidgets('כל הקשר מציג את הפריטים שלו בלבד', (tester) async {
      expect(labels(await entries(tester)), ['---', 'פעולה על העמוד']);
      expect(
        labels(await entries(tester, hasSelection: true, loadedText: 'א')),
        ['---', 'חפש'],
      );
    });

    testWidgets('פריט בלי contexts אינו מופיע ב-PDF', (tester) async {
      expect(await entries(tester, records: [items.first]), isEmpty);
    });

    testWidgets('טקסט טעון נמסר כמו שהוא, בלי קריאה נוספת', (tester) async {
      final clicks = <Map<String, dynamic>>[];
      var reads = 0;
      final menu = await entries(
        tester,
        hasSelection: true,
        loadedText: 'מאימתי',
        readSelectedText: () async {
          reads++;
          return '';
        },
        clicks: clicks,
      );
      await click(tester, menu.last);
      expect(reads, 0);
      expect(clicks.single['selectedText'], 'מאימתי');
      expect(clicks.single['currentIndex'], 3);
      expect(clicks.single['currentBook'], 'ברכות');
    });

    testWidgets('בחירה שעמודיה לא נטענו נקראת בזמן הלחיצה', (tester) async {
      final clicks = <Map<String, dynamic>>[];
      final menu = await entries(tester, hasSelection: true, clicks: clicks);
      await click(tester, menu.last);
      expect(clicks.single['selectedText'], 'נקרא בלחיצה');
    });

    testWidgets('מסמך שאוסר העתקה מוסר את הלחיצה בלי הטקסט', (tester) async {
      final clicks = <Map<String, dynamic>>[];
      final menu = await entries(
        tester,
        hasSelection: true,
        loadedText: 'מאימתי',
        copyAllowed: false,
        clicks: clicks,
      );
      await click(tester, menu.last);
      expect(clicks.single['selectedText'], isEmpty);
    });

    testWidgets('כשל בקריאת הבחירה מוסר את הלחיצה בלי הטקסט', (tester) async {
      final clicks = <Map<String, dynamic>>[];
      final menu = await entries(
        tester,
        hasSelection: true,
        readSelectedText: () async => throw StateError('page not loaded'),
        clicks: clicks,
      );
      await click(tester, menu.last);
      expect(clicks.single['selectedText'], isEmpty);
    });
  });
}
