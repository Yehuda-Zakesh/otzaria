import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

/// TOC עם רשומה לכל שורת כותרת — כמו בספר אמיתי, שבו שורות השבירה של
/// הקריאה הרציפה הן שורות ה-TOC.
List<TocEntry> headerToc(List<String> lines) => [
  for (var i = 0; i < lines.length; i++)
    if (isReadingHeaderLine(lines[i])) TocEntry(text: lines[i], index: i),
];

/// סגמנטים כמו בקורא; בלי [breakLines] השבירות הן שורות [headerToc].
ReadingSegments buildReadingSegments(
  List<String> lines, {
  required bool continuous,
  List<bool>? loadedLineFlags,
  Iterable<int>? breakLines,
}) => ReadingSegments(
  layout: continuous
      ? ReadingLayout.continuous(
          lineCount: lines.length,
          breakLines: breakLines ?? readingBreakLines(headerToc(lines)),
        )
      : ReadingLayout.identity(lines.length),
  content: lines,
  loadedLineFlags: loadedLineFlags,
);
