import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';

// המימוש הקודם של referenceFromPageNumber, כאורקל.
String _oracle(
  int pageNumber,
  List<PdfOutlineNode>? outline, [
  String? bookTitle,
]) {
  if (outline == null) return "";

  List<String> texts = [];

  void searchOutline(List<PdfOutlineNode> entries, {int level = 0}) {
    for (final entry in entries) {
      final entryPage = entry.dest?.pageNumber;
      if (entryPage == null) continue;
      if (entryPage > pageNumber) return;
      if (level + 1 > texts.length) {
        texts.add(entry.title);
      } else {
        texts[level] = entry.title;
        texts = texts.getRange(0, level + 1).toList();
      }

      searchOutline(entry.children, level: level + 1);
    }
  }

  searchOutline(outline);
  texts = texts.map((e) => e.trim()).toList();
  if (bookTitle != null && texts.isNotEmpty && texts.first == bookTitle) {
    texts = texts.sublist(1);
  }
  return texts.join(', ');
}

List<PdfOutlineNode> _randomOutline(Random rnd, int depth) => [
  for (var i = 0; i < rnd.nextInt(5); i++)
    PdfOutlineNode(
      title: "${[' ספר', 'פרק ', 'דף', 'ספר'][rnd.nextInt(4)]}$i",
      dest: rnd.nextInt(6) == 0
          ? null
          : PdfDest(1 + rnd.nextInt(30), PdfDestCommand.fit, null),
      children: depth == 0 ? const [] : _randomOutline(rnd, depth - 1),
    ),
];

void main() {
  test('referenceFromPageNumber זהה למימוש הקודם על outline אקראי (perf)', () {
    final rnd = Random(3);
    expect(referenceFromPageNumber(1, null), _oracle(1, null));
    for (var round = 0; round < 300; round++) {
      final outline = _randomOutline(rnd, rnd.nextInt(4));
      for (var page = 0; page <= 31; page++) {
        expect(referenceFromPageNumber(page, outline), _oracle(page, outline));
        expect(
          referenceFromPageNumber(page, outline, 'ספר0'),
          _oracle(page, outline, 'ספר0'),
        );
      }
    }
  });
}
