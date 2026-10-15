import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_browser.dart';

Category _category(String title) => Category(
  title: title,
  description: 'תיאור מלא לכפתור המידע',
  shortDescription: 'תיאור קצר',
  order: 0,
  subCategories: [],
  books: [],
  parent: null,
);

void main() {
  group('ניווט חיצים ברשת הספרייה', () {
    late List<FocusNode> nodes;
    late int exitTopCount;

    tearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });

    /// רוחב 600 → שתי עמודות (600 ~/ 250); שישה כרטיסים = שלוש שורות.
    Widget buildGrid() {
      nodes = List.generate(6, (i) => FocusNode(debugLabel: 'card$i'));
      exitTopCount = 0;
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: Center(
              child: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: MyGridView(
                    onExitTop: () => exitTopCount++,
                    items: [
                      for (var i = 0; i < 6; i++)
                        CategoryGridItem(
                          category: _category('פריט $i'),
                          onCategoryClickCallback: () {},
                          focusNode: nodes[i],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    int? focusedIndex() {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].hasPrimaryFocus) return i;
      }
      return null;
    }

    testWidgets('חיצי צד עוברים ברצף בין הכרטיסים בלבד', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[0].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focusedIndex(), 1);
    });

    testWidgets('חיצי צד ממשיכים ברצף גם במעבר בין שורות', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[1].requestFocus();
      await tester.pump();

      // מסוף השורה הראשונה לתחילת השנייה — בלי לברוח לרכיב צדדי.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 2);
    });

    testWidgets('מעלה ומטה נעים בין שורות באותו טור', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[0].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedIndex(), 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedIndex(), 4);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedIndex(), 2);
    });

    testWidgets('בקצה הרשת הפוקוס נשאר על הכרטיס ולא בורח החוצה', (
      tester,
    ) async {
      await tester.pumpWidget(buildGrid());
      nodes[5].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedIndex(), 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedIndex(), 5);
    });

    testWidgets('חץ מעלה מהשורה הראשונה מפעיל onExitTop', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[1].requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(exitTopCount, 1);
    });

    testWidgets('כפתור המידע שבכרטיס מוחרג ממסלול ה-Tab', (tester) async {
      await tester.pumpWidget(buildGrid());
      nodes[0].requestFocus();
      await tester.pump();

      // בלי ההחרגה Tab היה עוצר על ה-IconButton של המידע בתוך הכרטיס.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedIndex(), 1);
    });
  });

  group('רשת גוללת ארוכה', () {
    const count = 300;
    late List<FocusNode> nodes;
    late int exitTopCount;

    tearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
    });

    /// 600×600 → שתי עמודות; 300 כרטיסים = 150 שורות, רובן מחוץ לתצוגה.
    Widget buildGrid({required bool scrollable}) {
      nodes = List.generate(count, (i) => FocusNode(debugLabel: 'card$i'));
      exitTopCount = 0;
      final grid = MyGridView(
        scrollable: scrollable,
        onExitTop: () => exitTopCount++,
        items: [
          for (var i = 0; i < count; i++)
            CategoryGridItem(
              category: _category('פריט $i'),
              onCategoryClickCallback: () {},
              focusNode: nodes[i],
            ),
        ],
      );
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            child: Center(
              child: SizedBox(
                width: 600,
                height: 600,
                child: scrollable ? grid : SingleChildScrollView(child: grid),
              ),
            ),
          ),
        ),
      );
    }

    int? focusedIndex() {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].hasPrimaryFocus) return i;
      }
      return null;
    }

    testWidgets('רשת גוללת בונה רק את הכרטיסים שבתצוגה', (tester) async {
      await tester.pumpWidget(buildGrid(scrollable: true));
      final built = find.byType(CategoryGridItem).evaluate().length;
      expect(built, greaterThan(0));
      expect(built, lessThan(count ~/ 5));
    });

    for (final scrollable in [false, true]) {
      testWidgets(
        'מטה עובר את כל השורות ומעלה חוזר לחיפוש (scrollable: $scrollable)',
        (tester) async {
          await tester.pumpWidget(buildGrid(scrollable: scrollable));
          nodes[1].requestFocus();
          await tester.pump();

          for (var row = 1; row < count ~/ 2; row++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pump();
            expect(focusedIndex(), row * 2 + 1);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          expect(focusedIndex(), count - 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(focusedIndex(), count - 2);

          for (var row = count ~/ 2 - 2; row >= 0; row--) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await tester.pump();
            expect(focusedIndex(), row * 2);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
          expect(exitTopCount, 1);
        },
      );
    }
  });

  group('resolveLibraryBackspaceAction', () {
    test('בשדה החיפוש הריק של הספרייה — עולים תיקייה', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: true,
          isLibrarySearchFocused: true,
          isSearchTextEmpty: true,
        ),
        LibraryBackspaceAction.navigateUp,
      );
    });

    test('בשדה החיפוש עם טקסט — המקש נשאר מחיקת תו', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: true,
          isLibrarySearchFocused: true,
          isSearchTextEmpty: false,
        ),
        LibraryBackspaceAction.none,
      );
    });

    test('בשדה טקסט אחר — המקש נשאר מחיקת תו גם כשהוא ריק', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: true,
          isLibrarySearchFocused: false,
          isSearchTextEmpty: true,
        ),
        LibraryBackspaceAction.none,
      );
    });

    test('פוקוס על כרטיס בלי חיפוש פעיל — עולים תיקייה', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: false,
          isLibrarySearchFocused: false,
          isSearchTextEmpty: true,
        ),
        LibraryBackspaceAction.navigateUp,
      );
    });

    test('פוקוס על כרטיס בזמן חיפוש פעיל — ניקוי החיפוש תחילה', () {
      expect(
        resolveLibraryBackspaceAction(
          isEditableTextFocused: false,
          isLibrarySearchFocused: false,
          isSearchTextEmpty: false,
        ),
        LibraryBackspaceAction.clearSearch,
      );
    });
  });
}
