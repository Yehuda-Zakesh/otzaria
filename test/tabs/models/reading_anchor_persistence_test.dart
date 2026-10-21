import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/utils/bookmark_from_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

import '../../helpers/memory_settings_cache.dart';

class _DelayedBook extends TextBook {
  _DelayedBook() : super(title: 'ספר בדיקה');

  final started = Completer<void>();
  final ready = Completer<List<TocEntry>>();

  @override
  Future<List<TocEntry>> get tableOfContents {
    if (!started.isCompleted) started.complete();
    return ready.future;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));
  const anchor = ReadingAnchor(
    line: 12,
    intraLineFraction: 0.9,
    alignment: 0.2,
  );

  test('טאב ושכפול שומרים את השבר בתוך השורה ואת גובה העוגן', () {
    final original = TextBookTab(
      book: TextBook(title: 'ספר בדיקה'),
      index: 12,
      initialReadingAnchor: anchor,
    );
    addTearDown(original.dispose);
    final restored = TextBookTab.fromJson(original.toJson());
    addTearDown(restored.dispose);
    final clone = original.clone() as TextBookTab;
    addTearDown(clone.dispose);
    expect(restored.index, 12);
    expect(restored.readingAnchor, anchor);
    expect(clone.readingAnchor, anchor);
    expect(restored.lines.position.value!.intraLineFraction, 0.9);
  });

  test('סימנייה והיסטוריה משחזרות עוגן דרך מסלול הפתיחה המשותף', () {
    final bookmark = Bookmark(
      ref: 'ספר בדיקה פרק א',
      book: TextBook(title: 'ספר בדיקה'),
      index: 12,
      readingAnchor: anchor,
    );
    final saved = Bookmark.fromJson(bookmark.toJson());
    expect(saved.copyWith(label: 'מילים חשובות').readingAnchor, anchor);
    final tab = tabFromBookmark(saved) as TextBookTab;
    addTearDown(tab.dispose);
    expect(tab.readingAnchor, anchor);
  });

  test('סימנייה לוכדת את הנקודה לפני המתנה לכתובת הספר', () async {
    final book = _DelayedBook();
    final tab = TextBookTab(
      book: book,
      index: 12,
      initialReadingAnchor: anchor,
    );
    addTearDown(tab.dispose);
    final saving = bookmarkFromReadingTab(tab, useStoredPositionFallback: true);
    await book.started.future;
    await tab.lines.jumpToLine(80, intraLineFraction: 0.3);
    book.ready.complete([]);
    final bookmark = (await saving)!;
    expect(bookmark.index, 12);
    expect(bookmark.readingAnchor, anchor);
  });

  test('סימנייה לטאב שלא נמדד שומרת את מיקום השורה בלי עוגן מלאכותי', () async {
    final book = _DelayedBook()..ready.complete([]);
    final tab = TextBookTab(book: book, index: 0);
    addTearDown(tab.dispose);
    final bookmark = (await bookmarkFromReadingTab(
      tab,
      useStoredPositionFallback: true,
    ))!;
    expect(bookmark.index, 0);
    expect(bookmark.readingAnchor, isNull);
    final restored = tabFromBookmark(bookmark) as TextBookTab;
    addTearDown(restored.dispose);
    expect(restored.lines.captureAnchor(), isNull);
  });

  test('JSON ישן או עוגן פגום ממשיכים להיפתח לפי מספר השורה', () {
    for (final value in [
      null,
      'invalid',
      {'line': -1},
      {'line': 12},
    ]) {
      final restored = TextBookTab.fromJson({
        'title': 'ספר בדיקה',
        'initalIndex': 12,
        'commentators': <String>[],
        'showLeftPane': false,
        'readingAnchor': value,
      });
      addTearDown(restored.dispose);
      expect(restored.index, 12);
      expect(restored.readingAnchor.intraLineFraction, 0);
    }
    expect(
      ReadingAnchor.tryFromJson({
        'line': 12,
        'intraLineFraction': double.nan,
        'alignment': 0.2,
      }),
      isNull,
    );
  });
}
