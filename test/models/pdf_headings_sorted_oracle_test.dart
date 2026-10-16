import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/pdf_headings.dart';

// המימוש הקודם של getSortedHeadings, כאורקל.
List<MapEntry<String, int>> _oracle(Map<String, int> headingsMap) {
  final entries = headingsMap.entries.toList();
  entries.sort((a, b) => a.value.compareTo(b.value));
  return entries;
}

void main() {
  test('getSortedHeadings זהה למימוש הקודם, גם בקריאות חוזרות (perf)', () {
    final rnd = Random(9);
    for (var round = 0; round < 200; round++) {
      final map = <String, int>{
        for (var i = 0; i < rnd.nextInt(60); i++) 'כותרת $i': rnd.nextInt(20),
      };
      final headings = PdfHeadings(headingsMap: map, bookTitle: 'ספר');
      final expected = _oracle(map);
      for (var call = 0; call < 3; call++) {
        expect(
          headings.getSortedHeadings().map((e) => (e.key, e.value)),
          orderedEquals(expected.map((e) => (e.key, e.value))),
        );
      }
    }
  });
}
