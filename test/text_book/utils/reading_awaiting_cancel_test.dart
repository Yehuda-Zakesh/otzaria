import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

void main() {
  testWidgets('ביטול אחרי נחיתה על פסקה לא טעונה שומר את העוגן החדש בטעינה', (
    tester,
  ) async {
    const viewportHeight = 600.0;
    const lineHeight = 100.0;
    const loadedPrefixHeight = 200.0;
    const targetLine = 30;
    final content = List.generate(40, (index) => 'שורה $index');
    var segments = buildReadingSegments(
      content,
      continuous: true,
      loadedLineFlags: List.generate(content.length, (index) => index != 0),
    );
    final lines = LineScrollController();
    final binding = ReadingViewportBinding(
      segments: () => segments,
      viewportExtent: () => viewportHeight,
    );
    lines.attach(binding);
    addTearDown(() async {
      lines.detach(binding);
      await tester.pumpWidget(const SizedBox.shrink());
      lines.dispose();
    });
    late StateSetter rebuild;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: viewportHeight,
            child: StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return lines.trackUserScroll(
                  ScrollablePositionedList.builder(
                    itemScrollController: lines.itemController,
                    itemPositionsListener: lines.positionsListener,
                    itemCount: segments.length,
                    estimateExtent: (_, width) => content.length * lineHeight,
                    itemBuilder: (_, item) => ReaderItemBox(
                      item: item,
                      boxes: lines.itemBoxes,
                      child: segments[item].isLoaded
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: loadedPrefixHeight),
                                for (
                                  var line = 0;
                                  line < content.length;
                                  line++
                                )
                                  ReaderLineBlock(
                                    lineIndex: line,
                                    child: SizedBox(
                                      height: lineHeight,
                                      child: Text(content[line]),
                                    ),
                                  ),
                              ],
                            )
                          : SizedBox(height: content.length * lineHeight),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(segments.length, 1);
    expect(segments[0].isLoaded, isFalse);
    final scroll = lines.itemController.scrollController!;
    scroll.jumpTo(1600);
    await tester.pumpAndSettle();
    final beforeNavigation = lines.captureAnchor()!;

    final navigation = lines.jumpToLine(targetLine);
    await tester.pumpAndSettle();
    await navigation;
    expect(lines.captureAnchor()!.line, targetLine);
    expect(segments[0].isLoaded, isFalse);

    // אין פריים בין הלחיצה לטעינה: מדידת ביטול אינה יכולה להגיע מגלילה נוספת.
    final pointer = await tester.startGesture(
      tester.getCenter(find.byType(ScrollablePositionedList)),
    );
    await pointer.up();
    final interrupted = lines.captureAnchor()!;
    expect(interrupted.line, isNot(targetLine));
    expect(interrupted.line, isNot(beforeNavigation.line));
    rebuild(() {
      segments = buildReadingSegments(content, continuous: true);
    });
    await tester.pumpAndSettle();

    final extent = lines.itemBoxes.lineExtent(0, interrupted.line)!;
    final itemHeight = lines.itemBoxes.boxForItem(0)!.size.height;
    final expectedOffset =
        (extent.top +
                interrupted.intraLineFraction * (extent.bottom - extent.top)) *
            itemHeight -
        interrupted.alignment * viewportHeight;
    expect(scroll.offset, closeTo(expectedOffset, 0.5));
    expect(lines.captureAnchor()!.line, interrupted.line);
    expect(lines.captureAnchor()!.line, isNot(beforeNavigation.line));
    expect(lines.captureAnchor()!.line, isNot(targetLine));
    expect(tester.takeException(), isNull);
  });
}
