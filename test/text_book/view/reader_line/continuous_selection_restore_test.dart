import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const lines = ['<h2>פרק א</h2>', '<b>אָבּ</b>', 'גַּד'];
  final layout = ReadingLayout.continuous(
    lineCount: lines.length,
    breakLines: const [0],
  );
  final paragraphs = readerSelectionParagraphs(
    layout: layout,
    lines: lines,
    baseIndex: 1,
    sectionHeadings: const {
      2: ['כּוֹתֶרֶת', 'מְנֻקֶּדֶת'],
    },
  );

  for (final missingMark in [false, true]) {
    test(
      'מבנה הקורא ושחזור הבחירה שומרים ניקוד ומשמיטים כותרות ($missingMark)',
      () {
        final restored = restoreSelectedTextLineBreaksDetailed(
          selectedText:
              'אָבּ כּוֹתֶרֶת · מְנֻקֶּדֶת ${missingMark ? 'גַד' : 'גַּד'}',
          visibleLines: [
            for (final raw in lines.skip(1))
              renderSelectionLine(
                rawText: raw,
                settings: const RenderSettings(),
              ),
          ],
          paragraphs: paragraphs,
        );

        expect(restored, (
          text: missingMark ? 'אָבּ גַד' : 'אָבּ גַּד',
          startLine: 0,
          endLine: 1,
          startColumn: 0,
          ambiguous: false,
        ));
      },
    );
  }
}
