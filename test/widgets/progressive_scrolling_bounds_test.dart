import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

void main() {
  for (final down in [false, true]) {
    testWidgets('החזקת חץ בקצה אינה יוצרת overscroll: down=$down', (
      tester,
    ) async {
      final item = ItemScrollController();
      final focus = FocusNode();
      var navigations = 0;
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProgressiveScroll(
            scrollController: item,
            focusNode: focus,
            onNavigationStart: () => navigations++,
            maxSpeed: 1000,
            accelerationFactor: 1000,
            curve: 0,
            child: ScrollablePositionedList.builder(
              itemScrollController: item,
              itemCount: 100,
              estimateExtent: (_, width) => 100,
              itemBuilder: (_, index) => const SizedBox(height: 100),
            ),
          ),
        ),
      );
      final position = item.scrollController!.position;
      position.jumpTo(
        down ? position.maxScrollExtent : position.minScrollExtent,
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      final key = down
          ? LogicalKeyboardKey.arrowDown
          : LogicalKeyboardKey.arrowUp;
      await tester.sendKeyDownEvent(key);
      try {
        for (var frame = 0; frame < 10; frame++) {
          if (frame > 0) await tester.sendKeyRepeatEvent(key);
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            position.pixels,
            inInclusiveRange(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
        }
        expect(navigations, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
      } finally {
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
      }
    });
  }
}
