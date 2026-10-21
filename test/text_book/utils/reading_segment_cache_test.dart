import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

void main() {
  test('ביקור בספר שלם אינו משאיר את כל הפריטים במטמון', () {
    final content = List.generate(10000, (index) => 'פסקה $index');
    final segments = ReadingSegments(
      layout: ReadingLayout.identity(content.length),
      content: content,
      maxCachedSegments: 20,
      maxCachedCharacters: 200,
    );
    for (var item = 0; item < segments.length; item++) {
      expect(segments[item].text, content[item]);
    }
    expect(segments.debugBuiltCount, lessThanOrEqualTo(20));
    expect(segments.debugCachedCharacters, lessThanOrEqualTo(200));
    expect(segments.first.text, content.first);
  });

  test('המטמון שומר פריט שנקרא שוב ומפנה את הפחות שימושי', () {
    final segments = ReadingSegments(
      layout: const ReadingLayout.identity(4),
      content: const ['א', 'ב', 'ג', 'ד'],
      maxCachedSegments: 2,
    );
    final first = segments[0];
    final second = segments[1];
    expect(segments[0], same(first));
    segments[2];
    expect(segments[0], same(first));
    expect(segments[1], isNot(same(second)));
  });

  test('פסקה גלויה גדולה נשמרת עד היציאה מהתצוגה', () {
    final content = ['א' * 1000, 'ב' * 1000, 'ג' * 1000];
    final segments = ReadingSegments(
      layout: const ReadingLayout.identity(3),
      content: content,
      maxCachedSegments: 2,
      maxCachedCharacters: 20,
    );
    segments.retainVisibleItems([0]);
    final visible = segments[0];
    segments[1];
    segments[2];
    expect(segments[0], same(visible));
    segments.retainVisibleItems([2]);
    expect(segments.debugBuiltCount, 0);
    expect(segments[2].text, content[2]);
    expect(segments.debugBuiltCount, 1);
  });

  test('פסקה רציפה שפונתה נבנית שוב עם אותם טקסט וטווחי שורות', () {
    final content = List.generate(600, (index) => 'מילה $index');
    final segments = ReadingSegments(
      layout: ReadingLayout.continuous(lineCount: 600, breakLines: const []),
      content: content,
      maxCachedSegments: 1,
    );
    final first = segments[0];
    segments[2];
    final rebuilt = segments[0];
    expect(rebuilt, isNot(same(first)));
    expect(rebuilt.text, first.text);
    expect(rebuilt.isHeader, first.isHeader);
    expect(rebuilt.isLoaded, first.isLoaded);
    expect(rebuilt.sourceLineIndices, first.sourceLineIndices);
    expect(
      rebuilt.lineRanges.map(
        (range) => (range.lineIndex, range.start, range.end),
      ),
      first.lineRanges.map(
        (range) => (range.lineIndex, range.start, range.end),
      ),
    );
  });
}
