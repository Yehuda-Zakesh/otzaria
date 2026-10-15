import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/view/commentators_tab_screen.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

// המימוש הקודם, מועתק כלשונו — אורקל להשוואה.
String _oldGetParaPreview(String rawText) {
  final plain = utils
      .stripHtmlIfNeeded(rawText)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return '';
  const maxChars = 40;
  if (plain.length <= maxChars) return plain;
  final lastSpace = plain.lastIndexOf(' ', maxChars);
  final cut = lastSpace > 0 ? lastSpace : maxChars;
  return '${plain.substring(0, cut)}...';
}

bool _oldIsDuplicateChapterChild(
  TocEntry chapter,
  TocEntry child,
  String preview,
) {
  if (child.index != chapter.index) {
    return false;
  }
  final normalizedChapter = chapter.text.trim();
  final normalizedChild = child.text.trim();
  final normalizedPreview = preview.trim();
  return normalizedChild == normalizedChapter ||
      normalizedPreview == normalizedChapter ||
      normalizedPreview.startsWith(normalizedChapter);
}

String _oldPreviewForChild(
  TocEntry chapter,
  TocEntry child,
  List<String> content,
) {
  final textFromContent = child.index < content.length
      ? content[child.index]
      : '';
  return textFromContent.trim().isNotEmpty
      ? _oldGetParaPreview(textFromContent)
      : child.text;
}

void main() {
  test('isDuplicateChapterChild זהה למימוש הקודם (perf)', () {
    final rnd = Random(7);
    const texts = [
      '',
      '  ',
      'פרק א',
      ' פרק א ',
      'פרק א - בראשית',
      '<h2>פרק א</h2>',
      '<b>פרק</b> א',
      'בראשית ברא אלהים את השמים ואת הארץ והארץ היתה תהו ובהו',
      '<p>בראשית   ברא\n\tאלהים</p>',
      'פרקא',
      'א',
    ];
    var checked = 0;
    for (var round = 0; round < 3000; round++) {
      final content = List.generate(
        rnd.nextInt(6),
        (_) => texts[rnd.nextInt(texts.length)],
      );
      final chapter = TocEntry(
        text: texts[rnd.nextInt(texts.length)],
        index: rnd.nextInt(7),
      );
      final child = TocEntry(
        text: texts[rnd.nextInt(texts.length)],
        index: rnd.nextBool() ? chapter.index : rnd.nextInt(7),
        parent: chapter,
      );
      expect(
        isDuplicateChapterChild(chapter, child, content),
        _oldIsDuplicateChapterChild(
          chapter,
          child,
          _oldPreviewForChild(chapter, child, content),
        ),
        reason:
            'chapter=${chapter.text}@${chapter.index} '
            'child=${child.text}@${child.index} content=$content',
      );
      checked++;
    }
    expect(checked, 3000);
  });
}
