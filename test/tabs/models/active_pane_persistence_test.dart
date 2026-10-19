import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../../helpers/memory_settings_cache.dart';

/// החלונית הפעילה של טאב מפוצל לא נשמרה כלל: מעבר בין שולחנות עבודה החזיר
/// תמיד את החלונית הראשונה. הערך יושב ברמת שולחן העבודה — "איזו חלונית
/// פעילה בטאב הנוכחי" — ולא בתוך `CombinedTab.toJson`, כי הוא נתון אחד
/// לשולחן עבודה בדיוק כמו `currentTab`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab pdf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/nonexistent/$title.pdf'),
    pageNumber: 1,
  );

  CombinedTab split({String right = 'ימין', String left = 'שמאל'}) =>
      CombinedTab(rightTab: pdf(right), leftTab: pdf(left));

  test('round-trip — "right", "left" ומפתח נעדר', () {
    for (final side in [kRightPaneSide, kLeftPaneSide, null]) {
      final workspace = Workspace(
        name: 'שולחן',
        tabs: [split()],
        activeTabIndex: 0,
        activePane: side,
      );
      addTearDown(() {
        for (final tab in workspace.tabs) {
          tab.dispose();
        }
      });

      final json = workspace.toJson();
      expect(
        json.containsKey('activePane'),
        side != null,
        reason: 'side=$side',
      );

      final restored = Workspace.fromJson(json);
      addTearDown(() {
        for (final tab in restored.tabs) {
          tab.dispose();
        }
      });
      expect(restored.activePane, side, reason: 'side=$side');
    }
  });

  test('ערך פגום נקרא כ-null ואינו זורק', () {
    for (final bad in <Object>['middle', 3, <String, dynamic>{}]) {
      final restored = Workspace.fromJson({
        'id': 'w1',
        'name': 'שולחן',
        'tabs': <dynamic>[],
        'currentTab': 0,
        'activePane': bad,
      });
      expect(restored.activePane, isNull, reason: 'bad=$bad');
    }
  });

  test('כיוון RTL — "right" הוא rightTab, שהוא גם panes.first', () {
    // rightTab הוא הראשון בסדר התצוגה (הימני ב-RTL). היפוך הסריאליזציה
    // היה מחליף בשקט בין החלוניות, ולכן ההשוואה היא identical ולא כותרת.
    final tab = split(right: 'ימין', left: 'שמאל');
    addTearDown(tab.dispose);

    expect(identical(paneForSide(tab, kRightPaneSide), tab.rightTab), isTrue);
    expect(identical(paneForSide(tab, kLeftPaneSide), tab.leftTab), isTrue);
    expect(identical(tab.panes.first, tab.rightTab), isTrue);

    expect(activePaneSideOf(tab, tab.rightTab), kRightPaneSide);
    expect(activePaneSideOf(tab, tab.leftTab), kLeftPaneSide);
    // חלונית שאינה של הטאב הזה, וטאב שאינו מפוצל.
    expect(activePaneSideOf(tab, pdf('זר')), isNull);
    expect(activePaneSideOf(pdf('בודד'), null), isNull);
    expect(paneForSide(pdf('בודד'), kRightPaneSide), isNull);
  });

  test('גיזום — טאב שהפך לחלונית בודדת אינו שומר צד', () {
    // `prunePanes` מסיר חלונית מפרשי PDF, ואחותה תופסת את מקום הטאב.
    // מרגע זה "right"/"left" חסר משמעות, ולכן המפתח לא נכתב.
    final survivor = pdf('שורדת');
    final commentators = PdfCommentatorsTab(sourceTab: pdf('מפרשים'));
    final workspace = Workspace(
      name: 'שולחן',
      tabs: [CombinedTab(rightTab: commentators, leftTab: survivor)],
      activeTabIndex: 0,
      activePane: kRightPaneSide,
    );
    addTearDown(() {
      for (final tab in workspace.tabs) {
        tab.dispose();
      }
    });

    final json = workspace.toJson();

    expect(json.containsKey('activePane'), isFalse);
    expect((json['tabs'] as List), hasLength(1));
    expect((json['tabs'] as List).first['type'], 'PdfBookTab');
  });

  test('currentTab שמומפה מחדש — הצד נבדק מול הטאב שאחרי המיפוי', () {
    // הטאב הראשון נושר בגיזום, ולכן האינדקס הפעיל מוזז. הצד נכתב רק אם
    // הטאב שבאינדקס החדש הוא זה שעדיין מפוצל.
    final dropped = PdfCommentatorsTab(sourceTab: pdf('נושר'));
    final kept = split(right: 'ימין', left: 'שמאל');
    final workspace = Workspace(
      name: 'שולחן',
      tabs: [dropped, kept],
      activeTabIndex: 1,
      activePane: kLeftPaneSide,
    );
    addTearDown(() {
      for (final tab in workspace.tabs) {
        tab.dispose();
      }
    });

    final json = workspace.toJson();

    expect((json['tabs'] as List), hasLength(1));
    expect(json['currentTab'], 0);
    expect(json['activePane'], kLeftPaneSide);

    final restored = Workspace.fromJson(json);
    addTearDown(() {
      for (final tab in restored.tabs) {
        tab.dispose();
      }
    });
    expect(restored.activeTabIndex, 0);
    expect(restored.tabs.single, isA<CombinedTab>());
    expect(
      identical(
        paneForSide(restored.tabs.single, restored.activePane),
        (restored.tabs.single as CombinedTab).leftTab,
      ),
      isTrue,
    );
  });

  test('טאב פעיל שאינו מפוצל — הצד אינו נכתב', () {
    final workspace = Workspace(
      name: 'שולחן',
      tabs: [pdf('בודד')],
      activeTabIndex: 0,
      activePane: kRightPaneSide,
    );
    addTearDown(() {
      for (final tab in workspace.tabs) {
        tab.dispose();
      }
    });

    expect(workspace.toJson().containsKey('activePane'), isFalse);
  });

  test('withTabs מנקה במפורש, copyWith משמר', () {
    final workspace = Workspace(
      name: 'שולחן',
      tabs: [split()],
      activeTabIndex: 0,
      activePane: kLeftPaneSide,
    );
    addTearDown(() {
      for (final tab in workspace.tabs) {
        tab.dispose();
      }
    });

    // שינוי שם אינו נוגע בחלונית הפעילה.
    expect(workspace.copyWith(name: 'אחר').activePane, kLeftPaneSide);
    // החלפת תוכן קובעת אותה מחדש — null כאן פירושו "אין", לא "אל תיגע".
    final replaced = workspace.withTabs(
      tabs: const <OpenedTab>[],
      activeTabIndex: 0,
      activePane: null,
    );
    expect(replaced.activePane, isNull);
  });
}
