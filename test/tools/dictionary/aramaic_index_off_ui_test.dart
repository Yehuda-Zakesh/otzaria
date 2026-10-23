import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jsonString = File('assets/dictionary.json').readAsStringSync();

  List<AramaicDictionaryEntry> rawEntries() {
    final raw = jsonDecode(jsonString) as Map<String, dynamic>;
    return [
      for (final entry
          in (raw['מילון פשיטא'] as List).whereType<Map<String, dynamic>>())
        if (entry.isNotEmpty)
          AramaicDictionaryEntry(
            aramaic: entry.keys.first,
            hebrew: entry[entry.keys.first].toString(),
          ),
    ];
  }

  Future<DictionaryLookupRepository> oracle() async {
    final entries = rawEntries();
    final repository = DictionaryLookupRepository(
      loadAramaicEntries: () async => entries,
    );
    await repository.ensureAramaicLoaded();
    return repository;
  }

  List<List<String>> shape(List<AramaicDictionaryEntry> entries) => [
    for (final e in entries) [e.aramaic, e.hebrew],
  ];

  test('פענוח המילון ובניית האינדקס רצים ב-isolate נפרד', () async {
    final index = await Isolate.run(
      () => DictionaryLookupRepository.decodeAramaicIndex(jsonString),
    );

    final expected = await oracle();
    expect(shape(index.entries), shape(expected.getAllAramaicEntries()));
    expect(index.index.length, index.entries.length);
    for (final term in index.terms) {
      expect(expected.findAramaicMatches(term), isNotEmpty, reason: term);
    }
  });

  test('טעינת ברירת המחדל מהנכס זהה לטעינה מרשימת הערכים', () async {
    final repository = DictionaryLookupRepository();
    await repository.ensureAramaicLoaded();
    final expected = await oracle();

    expect(
      shape(repository.getAllAramaicEntries()),
      shape(expected.getAllAramaicEntries()),
    );
    for (final entry in expected.getAllAramaicEntries()) {
      for (final query in [entry.aramaic, ...entry.aramaic.split(' ')]) {
        expect(
          shape(repository.findAramaicMatches(query)),
          shape(expected.findAramaicMatches(query)),
          reason: query,
        );
      }
    }
  });
}
