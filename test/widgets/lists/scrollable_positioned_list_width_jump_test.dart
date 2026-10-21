import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// גובה הפריטים תלוי ברוחב — כמו טקסט שנשבר לשורות נוספות בעמודה צרה.
Widget _list(double width, ItemScrollController c, ItemPositionsListener l) {
  return MaterialApp(
    home: Center(
      child: SizedBox(
        width: width,
        height: 400,
        child: ScrollablePositionedList.builder(
          itemScrollController: c,
          itemPositionsListener: l,
          itemCount: 200,
          itemBuilder: (context, index) =>
              SizedBox(height: 30 * (600 / width), child: Text('$index')),
        ),
      ),
    ),
  );
}

void main() {
  // issue #1542: בלי מפתחות ל-slivers שסביב ה-center, ילדים שנשמרו אחרי
  // jumpTo נשאו offsets מהרוחב הקודם והפריסה חרגה ממגבלת הסבבים.
  for (final sameFrame in [false, true]) {
    for (final target in [5, 60, 150]) {
      final when = sameFrame ? 'באותו פריים עם' : 'אחרי';
      testWidgets('קפיצה ל-$target $when שינוי הרוחב מגיעה ליעד', (
        tester,
      ) async {
        final controller = ItemScrollController();
        final listener = ItemPositionsListener.create();
        await tester.pumpWidget(_list(600, controller, listener));
        await tester.drag(
          find.byType(ScrollablePositionedList),
          const Offset(0, -1500),
        );
        await tester.pumpAndSettle();

        if (sameFrame) {
          controller.jumpTo(index: target);
          await tester.pumpWidget(_list(300, controller, listener));
        } else {
          await tester.pumpWidget(_list(300, controller, listener));
          controller.jumpTo(index: target);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final visible = listener.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .map((p) => p.index);
        expect(visible, contains(target));
      });
    }
  }
}
