import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

void main() {
  testWidgets('גלגלת בזמן ניווט מבטלת גם חזרה ליעד אחרי טעינה מאוחרת', (
    tester,
  ) async {
    final lines = LineScrollController();
    final content = List.generate(100, (i) => 'שורה $i');
    var segments = buildReadingSegments(
      content,
      continuous: false,
      loadedLineFlags: List.generate(100, (i) => i != 50),
    );
    final binding = ReadingViewportBinding(
      segments: () => segments,
      viewportExtent: () => 600,
    );
    lines.attach(binding);
    late StateSetter rebuild;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return lines.trackUserScroll(
              ScrollablePositionedList.builder(
                itemScrollController: lines.itemController,
                itemPositionsListener: lines.positionsListener,
                itemCount: 100,
                itemBuilder: (_, index) => SizedBox(
                  height: 80,
                  child: Text('${segments[index].text} $index'),
                ),
              ),
            );
          },
        ),
      ),
    );
    final navigation = lines.scrollToLine(
      50,
      duration: const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ScrollablePositionedList)),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();
    await navigation;
    final scroll = lines.itemController.scrollController!;
    final afterWheel = scroll.offset;
    expect(lines.captureAnchor()!.line, isNot(50));
    rebuild(() {
      segments = buildReadingSegments(content, continuous: false);
    });
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(afterWheel, 0.5));
    expect(lines.captureAnchor()!.line, isNot(50));
    lines.detach(binding);
    await tester.pumpWidget(const SizedBox());
    lines.dispose();
  });
}
