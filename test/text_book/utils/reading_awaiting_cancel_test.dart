import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
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
  testWidgets('טעינה שאינה משנה את גובה הפריט מדייקת את היעד שהמתין לה', (
    tester,
  ) async {
    const viewportHeight = 600.0;
    const targetLine = 30;
    final content = List.generate(40, (index) => 'שורה $index');
    // אותו גובה כולל לפני הטעינה ואחריה, אבל השורה נמצאת במקום אחר.
    double loadedLineHeight(int line) => line < targetLine ? 50 : 250;
    const itemHeight = targetLine * 50.0 + 10 * 250.0;
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
      _ReaderList(
        lines: lines,
        viewportHeight: viewportHeight,
        onBuild: (setState) => rebuild = setState,
        itemCount: () => segments.length,
        child: (item) => segments[item].isLoaded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var line = 0; line < content.length; line++)
                    ReaderLineBlock(
                      lineIndex: line,
                      child: SizedBox(
                        height: loadedLineHeight(line),
                        child: Text(content[line]),
                      ),
                    ),
                ],
              )
            : const SizedBox(height: itemHeight),
      ),
    );
    await tester.pumpAndSettle();
    expect(segments.length, 1);

    final navigation = lines.jumpToLine(targetLine);
    await tester.pumpAndSettle();
    await navigation;
    final scroll = lines.itemController.scrollController!;
    final beforeLoad = scroll.offset;

    rebuild(() {
      segments = buildReadingSegments(content, continuous: true);
    });
    await tester.pumpAndSettle();

    expect(lines.itemBoxes.boxForItem(0)!.size.height, itemHeight);
    final extent = lines.itemBoxes.lineExtent(0, targetLine)!;
    final expectedOffset =
        extent.top * itemHeight - kReadingAnchorAlignment * viewportHeight;
    expect(beforeLoad, isNot(closeTo(expectedOffset, 0.5)));
    expect(scroll.offset, closeTo(expectedOffset, 0.5));
    expect(lines.hasPendingTarget, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('גלילה ידנית לפסקה לא טעונה שומרת עוגן בטעינה בגובה זהה', (
    tester,
  ) async {
    const viewportHeight = 600.0;
    const targetLine = 30;
    final content = List.generate(40, (index) => 'שורה $index');
    // אותו גובה כולל לפני הטעינה ואחריה, אבל השורה נמצאת במקום אחר.
    double loadedLineHeight(int line) => line < targetLine ? 50 : 250;
    const itemHeight = targetLine * 50.0 + 10 * 250.0;
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
      _ReaderList(
        lines: lines,
        viewportHeight: viewportHeight,
        onBuild: (setState) => rebuild = setState,
        itemCount: () => segments.length,
        child: (item) => segments[item].isLoaded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var line = 0; line < content.length; line++)
                    ReaderLineBlock(
                      lineIndex: line,
                      child: SizedBox(
                        height: loadedLineHeight(line),
                        child: Text(content[line]),
                      ),
                    ),
                ],
              )
            : const SizedBox(height: itemHeight),
      ),
    );
    await tester.pumpAndSettle();
    expect(segments.length, 1);

    final scroll = lines.itemController.scrollController!;
    scroll.jumpTo(3000);
    await tester.pumpAndSettle();
    final anchor = lines.captureAnchor()!;
    expect(lines.hasPendingTarget, isFalse);
    final beforeLoad = scroll.offset;

    rebuild(() {
      segments = buildReadingSegments(content, continuous: true);
    });
    await tester.pumpAndSettle();

    expect(lines.itemBoxes.boxForItem(0)!.size.height, itemHeight);
    final extent = lines.itemBoxes.lineExtent(0, anchor.line)!;
    final expectedOffset =
        (extent.top + anchor.intraLineFraction * (extent.bottom - extent.top)) *
            itemHeight -
        anchor.alignment * viewportHeight;
    expect(beforeLoad, isNot(closeTo(expectedOffset, 0.5)));
    expect(scroll.offset, closeTo(expectedOffset, 0.5));
    expect(lines.captureAnchor()!.line, anchor.line);
    expect(lines.hasPendingTarget, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('בנייה מחדש בלי יעד ממתין ממשיכה לפרסם מיקומים', (tester) async {
    const viewportHeight = 600.0;
    final content = List.generate(40, (index) => 'שורה $index');
    final segments = buildReadingSegments(content, continuous: false);
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
      _ReaderList(
        lines: lines,
        viewportHeight: viewportHeight,
        onBuild: (setState) => rebuild = setState,
        itemCount: () => segments.length,
        child: (item) => SizedBox(height: 100, child: Text(content[item])),
      ),
    );
    await tester.pumpAndSettle();
    expect(lines.hasPendingTarget, isFalse);
    var notifications = 0;
    void count() => notifications++;
    lines.positionsListener.itemPositions.addListener(count);
    addTearDown(
      () => lines.positionsListener.itemPositions.removeListener(count),
    );

    for (var i = 0; i < 5; i++) {
      rebuild(() {});
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(notifications, greaterThan(0));
  });
}

/// רשימת קורא שנבנית מחדש דרך [onBuild], כמו בקורא האמיתי.
class _ReaderList extends StatelessWidget {
  const _ReaderList({
    required this.lines,
    required this.viewportHeight,
    required this.onBuild,
    required this.itemCount,
    required this.child,
  });

  final LineScrollController lines;
  final double viewportHeight;
  final void Function(StateSetter) onBuild;
  final int Function() itemCount;
  final Widget Function(int item) child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: viewportHeight,
        child: StatefulBuilder(
          builder: (_, setState) {
            onBuild(setState);
            return lines.trackUserScroll(
              ScrollablePositionedList.builder(
                itemScrollController: lines.itemController,
                itemPositionsListener: lines.positionsListener,
                itemCount: itemCount(),
                estimateExtent: (_, width) => 4000,
                itemBuilder: (_, item) => ReaderItemBox(
                  item: item,
                  boxes: lines.itemBoxes,
                  child: child(item),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
