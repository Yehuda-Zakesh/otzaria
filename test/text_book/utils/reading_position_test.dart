import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/reading_toc.dart';

ItemPosition _pos(int index, double leading, double trailing) => ItemPosition(
  index: index,
  itemLeadingEdge: leading,
  itemTrailingEdge: trailing,
);

void main() {
  final normal = buildReadingSegments(
    List.generate(100, (i) => 'שורה $i'),
    continuous: false,
  );
  // פסקה אחת של 10 שורות שוות אורך בין שתי כותרות.
  final paragraph = buildReadingSegments(
    [
      '<h2>א</h2>',
      for (var i = 1; i <= 10; i++) 'שורה מספר ${i.toString().padLeft(2, '0')}',
      '<h2>ב</h2>',
    ],
    continuous: true,
  );

  test('פריט שנגלל כולו מעל החלון אינו המיקום (issue #1358)', () {
    final position = readingPositionFromItems(normal, [
      _pos(0, -2.0, -1.2),
      _pos(37, -0.1, 0.4),
      _pos(38, 0.4, 0.9),
    ]);
    expect(position?.topLine, 37);
  });

  test('שייר הקטע הקודם מעל קו העוגן אינו המיקום (#1974)', () {
    final position = readingPositionFromItems(normal, [
      _pos(9, -0.2, kReadingAnchorAlignment),
      _pos(10, kReadingAnchorAlignment, 0.4),
      _pos(11, 0.4, 0.9),
    ]);
    expect(position?.topLine, 10);
    expect(position?.visibleLines, [10, 11]);
  });

  test('בראש הספר שורה שמעל קו העוגן היא המיקום', () {
    final position = readingPositionFromItems(normal, [
      _pos(0, 0, 0.03),
      _pos(1, 0.03, 0.06),
      _pos(2, 0.06, 0.09),
    ]);
    expect(position?.topLine, 0);
  });

  test('באמצע פסקה המיקום הוא השורה שעל קו העוגן, עם החלק שעבר אותו', () {
    // הפסקה (פריט 1) גבוהה פי 2 מהתצוגה; השורה הרביעית מתחילה בקו העוגן פחות
    // רבע שורה.
    const extent = 2.0;
    const lineExtent = extent / 10;
    const leading = kReadingAnchorAlignment - 3.25 * lineExtent;
    final position = readingPositionFromItems(paragraph, [
      _pos(1, leading, leading + extent),
    ])!;
    expect(position.topLine, 4);
    expect(position.intraLineFraction, closeTo(0.25, 0.05));
  });

  test('העוגן משחזר את אותה נקודה בטקסט', () {
    const extent = 2.0;
    const leading = kReadingAnchorAlignment - 0.65;
    final anchor = readingAnchorFromItems(paragraph, [
      _pos(1, leading, leading + extent),
    ])!;
    expect(anchor.line, 4);
    expect(anchor.alignment, kReadingAnchorAlignment);
    expect(anchor.intraLineFraction, closeTo(0.25, 0.05));
  });

  test('חלון הטעינה כולל פריט בשולי התצוגה שסונן מהשורות הגלויות', () {
    final position = readingPositionFromItems(paragraph, [
      _pos(0, -0.02, 0.02),
      _pos(1, 0.02, 0.98),
      _pos(2, 0.99, 1.2),
    ])!;
    expect(position.visibleLines, isNot(contains(11)));
    expect(position.windowFirstLine, 0);
    expect(position.windowLastLine, 11);
  });
}
