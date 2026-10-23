import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';

void main() {
  test('FFI: החלפת מצב, writer ומנוע שומרת את כל המסמכים והחתימות', () async {
    expect(await tryInitSearchEngine(), isTrue, reason: searchEngineSkipReason);
    expect(searchEngineLoadedLibraryPath, isNotNull);
    final root = await Directory.systemTemp.createTemp('economy_native_');
    Directory('${root.path}/normal').createSync();
    Directory('${root.path}/changing').createSync();
    final baseline = await SearchEngine.newInstance(
      path: '${root.path}/normal',
    );
    var changing = await SearchEngine.newInstance(
      path: '${root.path}/changing',
    );
    final provider = TantivyDataProvider.forTesting(Future.value(changing));
    final repository = IndexingRepository(provider);
    addTearDown(() async {
      baseline.dispose();
      changing.dispose();
      await root.delete(recursive: true);
    });

    Future<void> add(SearchEngine engine, int book) => engine.addTextBook(
      title: 'ספר $book',
      topics: '/בדיקה',
      filePath: 'book:$book',
      text: List.generate(
        1500,
        (line) => 'פרק $book שורה $line שלום עולם ייחודי',
      ).join('\n'),
      textStorage: TextStorage.inIndex,
    );

    for (var book = 0; book < 4; book++) {
      await add(baseline, book);
      if (book == 1) await repository.setEconomyIndexing(true);
      if (book == 2) {
        await changing.commit();
        changing.dispose();
        changing = await SearchEngine.newInstance(
          path: '${root.path}/changing',
        );
        provider.engine = Future.value(changing);
        await provider.engine;
        expect(repository.isEconomyIndexing, isTrue);
        await changing.openIndexWriter();
      }
      if (book == 3) {
        // בקשת שינוי מול כתיבה אמיתית מסונכרנת על נעילת ה-FFI.
        await Future.wait([
          add(changing, book),
          repository.setEconomyIndexing(false),
        ]);
      } else {
        await add(changing, book);
      }
    }
    await baseline.commit();
    await changing.commit();

    expect(repository.isEconomyIndexing, isFalse);
    final baselineCounts = await baseline.countDocumentsByFilePath();
    expect(
      baselineCounts,
      {'book:0': 1500, 'book:1': 1500, 'book:2': 1500, 'book:3': 1500},
    );
    expect(await changing.countDocumentsByFilePath(), baselineCounts);
    expect(
      await changing.getBookFingerprints(),
      await baseline.getBookFingerprints(),
    );
    final expectedHits = await baseline.countExact(
      query: 'ייחודי',
      facets: ['/'],
      matchNikud: false,
      matchTaamim: false,
    );
    expect(expectedHits, 6000);
    expect(
      await changing.countExact(
        query: 'ייחודי',
        facets: ['/'],
        matchNikud: false,
        matchTaamim: false,
      ),
      expectedHits,
    );
  });
}
