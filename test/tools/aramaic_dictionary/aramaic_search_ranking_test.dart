import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// המסלול הקודם: דירוג ו-RegExp מחושבים מחדש בכל השוואה של המיון.
List<Map<String, String>> _referenceSearch(
  List<Map<String, String>> data,
  String field,
  String query,
) {
  int rank(String text) {
    if (text == query) return 0;
    if (text.startsWith(query)) return 1;
    if (RegExp('(^|\\s)${RegExp.escape(query)}(\$|\\s)').hasMatch(text)) {
      return 2;
    }
    return 3;
  }

  return data.where((entry) => entry[field]!.contains(query)).toList()
    ..sort((a, b) {
      final textA = a[field]!;
      final textB = b[field]!;
      final rankCompare = rank(textA).compareTo(rank(textB));
      if (rankCompare != 0) return rankCompare;
      final posCompare = textA.indexOf(query).compareTo(textB.indexOf(query));
      if (posCompare != 0) return posCompare;
      return textA.length.compareTo(textB.length);
    });
}

List<Map<String, String>> _loadRealDictionary() {
  final json =
      jsonDecode(File('assets/dictionary.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final entry
        in (json['מילון פשיטא'] as List).whereType<Map<String, dynamic>>())
      if (entry.isNotEmpty)
        {
          'aramaicPlain': removeVolwels(entry.keys.first),
          'hebrewPlain': removeVolwels('${entry.values.first}'),
        },
  ];
}

int _medianMicros(void Function() run) {
  final samples = <int>[];
  for (var i = 0; i < 9; i++) {
    final sw = Stopwatch()..start();
    run();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void main() {
  final data = _loadRealDictionary();
  const queries = ['א', 'ד', 'ה', 'אי', 'מאי', 'של', 'לא', 'דא', 'זה'];

  test('הדירוג זהה למסלול הקודם על המילון האמיתי', () {
    expect(data.length, greaterThan(1000));
    for (final field in ['aramaicPlain', 'hebrewPlain']) {
      for (final query in queries) {
        final expected = _referenceSearch(data, field, query);
        final actual = rankAramaicMatches(data, field, query);
        expect(actual.length, expected.length, reason: '$field/$query');
        for (var i = 0; i < expected.length; i++) {
          expect(
            identical(actual[i], expected[i]),
            isTrue,
            reason: '$field/$query @$i',
          );
        }
      }
    }
  });

  test('הקשת אות ראשונה בכיוון עברי מהירה מהמסלול הקודם', () {
    for (var i = 0; i < 3; i++) {
      _referenceSearch(data, 'hebrewPlain', 'א');
      rankAramaicMatches(data, 'hebrewPlain', 'א');
    }
    final before = _medianMicros(
      () => _referenceSearch(data, 'hebrewPlain', 'א'),
    );
    final after = _medianMicros(
      () => rankAramaicMatches(data, 'hebrewPlain', 'א'),
    );
    // נמדד כפי 2-3; הסף רחב כדי לא להיכשל על מכונה עמוסה.
    expect(
      after * 1.3,
      lessThan(before),
      reason: 'before=$before after=$after',
    );
  });
}
