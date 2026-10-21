import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

void main() {
  for (final animated in [false, true]) {
    testWidgets('החלפת מבנה באמצע ניווט שומרת שורת מקור animated=$animated', (
      tester,
    ) async {
      final harness = _Harness();
      addTearDown(harness.lines.dispose);
      await tester.pumpWidget(harness.view());
      await tester.pumpAndSettle();
      final navigation = harness.lines.scrollToLine(
        50,
        intraLineFraction: 0.4,
        duration: animated ? const Duration(milliseconds: 250) : Duration.zero,
      );
      if (animated) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      harness.makeContinuous();
      await tester.pumpAndSettle();
      await navigation;
      expect(harness.lines.position.value!.topLine, 50);
      expect(harness.pointFor(50, 0.4), closeTo(30, 0.01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('ניווט חדש בזמן החלפת מבנה מבטל את יעד המקור הישן', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.lines.dispose);
    await tester.pumpWidget(harness.view());
    await tester.pumpAndSettle();
    final first = harness.lines.scrollToLine(50, intraLineFraction: 0.4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    harness.makeContinuous();
    final second = harness.lines.jumpToLine(850, intraLineFraction: 0.2);
    await tester.pumpAndSettle();
    await first;
    await second;
    expect(harness.lines.position.value!.topLine, 850);
    expect(harness.pointFor(850, 0.2), closeTo(30, 0.01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Harness {
  _Harness() {
    lines.attach(
      ReadingViewportBinding(
        segments: () => segments,
        viewportExtent: () => 600,
      ),
    );
  }

  final lines = LineScrollController();
  static final _content = [for (var i = 0; i < 1000; i++) 'שורת מקור $i'];
  ReadingSegments segments = ReadingSegments(
    layout: const ReadingLayout.identity(1000),
    content: _content,
  );
  late StateSetter _rebuild;

  void makeContinuous() => _rebuild(() {
    segments = ReadingSegments(
      layout: ReadingLayout.continuous(lineCount: 1000, breakLines: const []),
      content: _content,
    );
  });

  double pointFor(int line, double fraction) {
    final item = segments.layout.itemForLine(line);
    final box = lines.itemBoxes.boxForItem(item)!;
    final extent = lines.itemBoxes.lineExtent(item, line)!;
    return box.localToGlobal(Offset.zero).dy +
        box.size.height *
            (extent.top + fraction * (extent.bottom - extent.top));
  }

  Widget view() => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 600,
        child: StatefulBuilder(
          builder: (_, setState) {
            _rebuild = setState;
            return ScrollablePositionedList.builder(
              itemScrollController: lines.itemController,
              itemPositionsListener: lines.positionsListener,
              itemCount: segments.length,
              cacheExtentScreens: 0,
              estimateExtent: (_, _) => 100,
              estimationKey: segments.layout.continuous,
              itemBuilder: (_, item) => wrapReaderItem(
                item: item,
                layout: segments.layout,
                boxes: lines.itemBoxes,
                child: Column(
                  children: [
                    for (
                      var line = segments.layout.firstLineOf(item);
                      line <= segments.layout.lastLineOf(item);
                      line++
                    )
                      ReaderLineBlock(
                        lineIndex: line,
                        child: const SizedBox(height: 100),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
