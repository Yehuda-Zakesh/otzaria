import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/settings/dialogs/hidden_books_list_dialog.dart';

void main() {
  for (final touch in [false, true]) {
    testWidgets('אפשר לקרוא נתיבי הסתרה מלאים ב${touch ? 'מגע' : 'עכבר'}', (
      tester,
    ) async {
      final prefix = List.filled(12, 'קטגוריה ארוכה').join('/');
      final paths = {'$prefix/ספר ראשון', '$prefix/ספר שני'};
      HiddenLibrarySelection? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      saved = await showHiddenBooksListDialog(
                        context: context,
                        hidden: HiddenLibrarySelection(
                          bookKeys: const {},
                          categoryPaths: paths,
                        ),
                        titles: const {},
                      ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final path = paths.last;
      final label = find.text(path);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isTrue,
      );
      final row = find.byWidget(
        tester.widget<ListTile>(
          find.ancestor(of: label, matching: find.byType(ListTile)),
        ),
      );
      final height = tester.getSize(row).height;
      expect(find.byTooltip(path), findsOneWidget);
      if (touch) {
        await tester.longPress(label);
      } else {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(label));
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(path), findsNWidgets(2));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(path).last)
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.getSize(row).height, height);
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.text('בטל הסתרה')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('שמור'));
      await tester.pumpAndSettle();
      expect(saved!.categoryPaths, {paths.first});
      expect(paths, hasLength(2));
    });
  }

  testWidgets('קפיצה לסוף הרשימה לא בונה את כל השורות שבדרך (#3022)', (
    tester,
  ) async {
    final keys = [for (var i = 0; i < 3000; i++) 'ספר ${1000 + i}'];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showHiddenBooksListDialog(
                  context: context,
                  hidden: HiddenLibrarySelection(
                    bookKeys: keys.toSet(),
                    categoryPaths: const {},
                  ),
                  titles: const {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final controller = Scrollable.of(
      tester.element(find.text(keys.first)),
    ).position;
    var builtRows = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is ListTile) builtRows++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    controller.jumpTo(controller.maxScrollExtent);
    await tester.pump();

    expect(builtRows, lessThan(100));
    expect(find.text(keys.last), findsOneWidget);
  });
}
