import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_commentators_tab_screen.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

// המימוש הקודם של _getParagraphs, מועתק כלשונו — אורקל להשוואה.
List<({int lineIdx, String text})> _oldGetParagraphs(
  List<String>? lines,
  List<MapEntry<String, int>>? headings,
  int headingIdx,
) {
  if (lines == null) return const [];
  if (headings == null || headingIdx >= headings.length) return const [];
  final start = headings[headingIdx].value;
  final headingText = headings[headingIdx].key.trim();
  final end = headingIdx + 1 < headings.length
      ? headings[headingIdx + 1].value - 1
      : lines.length - 1;
  final result = <({int lineIdx, String text})>[];
  for (int i = start; i <= end && i < lines.length; i++) {
    final clean = utils.stripHtmlIfNeeded(lines[i]).trim();
    if (i == start && clean == headingText) {
      continue;
    }
    if (clean.isNotEmpty) result.add((lineIdx: i, text: clean));
  }
  return result;
}

void main() {
  test('headingParagraphs זהה למימוש הקודם, ועם limit — לתחילתו (perf)', () {
    final rnd = Random(11);
    const texts = [
      '',
      '   ',
      'פרק א',
      ' פרק א ',
      '<h2>פרק א</h2>',
      '<b></b>',
      'בראשית ברא אלהים',
      '<p>והארץ היתה <i>תהו</i> ובהו</p>',
    ];
    for (var round = 0; round < 2000; round++) {
      final lines = List.generate(
        rnd.nextInt(12),
        (_) => texts[rnd.nextInt(texts.length)],
      );
      final starts = List.generate(rnd.nextInt(4), (_) => rnd.nextInt(14))
        ..sort();
      final headings = [
        for (final s in starts) MapEntry(texts[rnd.nextInt(texts.length)], s),
      ];
      for (var h = 0; h <= headings.length; h++) {
        final expected = _oldGetParagraphs(lines, headings, h);
        expect(headingParagraphs(lines, headings, h), expected);
        for (final limit in [0, 1, 2]) {
          expect(
            headingParagraphs(lines, headings, h, limit: limit),
            expected.take(limit).toList(),
          );
        }
      }
    }
  });
}
