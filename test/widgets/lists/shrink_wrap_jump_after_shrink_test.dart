import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

const _heights = [40.0, 300.0, 40.0, 800.0];

/// כמו כרטיס המפרשים שבתוך הטקסט: רשימה מכווצת לתוכן בתוך גובה מרבי.
Widget _card(int count, ItemScrollController c, ItemPositionsListener l) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 400,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 600),
          child: ScrollablePositionedList.builder(
            itemScrollController: c,
            itemPositionsListener: l,
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: count,
            itemBuilder: (context, i) => SizedBox(
              key: ValueKey('item$i'),
              height: _heights[i],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // issue #2861: כיווץ המפרש האחרון מעגן מחדש על כותרתו; ב-SPL הישן הפריטים
  // שלפני העוגן צוירו לפי הגובה המרבי ולא לפי גובה הכרטיס, ונותר חלל ריק.
  testWidgets('קפיצה לפריט האחרון אחרי שהרשימה התקצרה מציירת בלי חלל', (
    tester,
  ) async {
    final controller = ItemScrollController();
    final listener = ItemPositionsListener.create();
    await tester.pumpWidget(_card(4, controller, listener));
    await tester.drag(
      find.byKey(const ValueKey('item1')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    final headerEdge = listener.itemPositions.value
        .firstWhere((p) => p.index == 2)
        .itemLeadingEdge;

    await tester.pumpWidget(_card(3, controller, listener));
    controller.jumpTo(index: 2, alignment: headerEdge);
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byType(ScrollablePositionedList));
    expect(card.height, 380);
    for (final (index, top) in [(0, 0.0), (1, 40.0), (2, 340.0)]) {
      final rect = tester.getRect(find.byKey(ValueKey('item$index')));
      expect(rect.top - card.top, top, reason: 'item$index');
    }
  });
}
