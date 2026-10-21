import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

void main() {
  testWidgets('שינוי רוחב שומר את הנקודה בתוך השורה לפני הציור הראשון', (
    tester,
  ) async {
    final lines = LineScrollController();
    final segments = buildReadingSegments(
      List.generate(100, (index) => 'שורה $index'),
      continuous: false,
    );
    final binding = ReadingViewportBinding(
      segments: () => segments,
      viewportExtent: () => 600,
    );
    lines.attach(binding);
    var width = 600.0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 600,
                child: ScrollPositionReanchor(
                  scrollController: lines.itemController,
                  positionsListener: lines.positionsListener,
                  preferredIndex: 20,
                  boxForIndex: lines.itemBoxes.boxForItem,
                  isNavigationActive: () => lines.isNavigating,
                  child: lines.trackUserScroll(
                    ScrollablePositionedList.builder(
                      itemScrollController: lines.itemController,
                      itemPositionsListener: lines.positionsListener,
                      itemCount: 100,
                      itemBuilder: (_, index) => ReaderItemBox(
                        item: index,
                        boxes: lines.itemBoxes,
                        child: ReaderLineBlock(
                          key: ValueKey('source-$index'),
                          lineIndex: index,
                          child: SizedBox(
                            height: 60000 / width,
                            child: Text('שורה $index'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final landing = lines.jumpToLine(20, intraLineFraction: 0.6);
    await tester.pumpAndSettle();
    await landing;
    double point() {
      final box = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('source-20')),
      );
      return box.localToGlobal(Offset(0, box.size.height * 0.6)).dy;
    }

    final before = point();
    expect(before, closeTo(30, 0.5));
    lines.keepViewAcrossRelayout();
    rebuild(() => width = 300);
    await tester.pump();
    expect(point(), closeTo(before, 0.5));
    expect(lines.navigationEpoch.value, 1);
    await tester.pumpAndSettle();
    expect(point(), closeTo(before, 0.5));
    lines.detach(binding);
    await tester.pumpWidget(const SizedBox());
    lines.dispose();
  });
}
