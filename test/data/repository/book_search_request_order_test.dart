import 'dart:async';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/book_search_worker.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

class _DelayedCatalogRepository extends DataRepository {
  final catalogRequested = Completer<void>();
  final catalog = Completer<List<ExternalLibraryBook>>();

  @override
  Future<List<ExternalLibraryBook>> getOtzarBooks() {
    catalogRequested.complete();
    return catalog.future;
  }
}

class _SearchCategory extends Category {
  _SearchCategory()
    : super(
        title: 'ספרים',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [
          TextBook(title: 'מבחן אלף'),
          TextBook(title: 'מבחן בית'),
        ],
        parent: null,
      );

  void Function()? onCategories;

  @override
  List<Category> getAllCategories() {
    final callback = onCategories;
    onCategories = null;
    callback?.call();
    return super.getAllCategories();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DelayedCatalogRepository repository;
  late _SearchCategory category;
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = _DelayedCatalogRepository();
    category = _SearchCategory();
  });
  tearDown(() => repository.bookSearchWorkerForTesting.dispose());

  for (final finishLatestFirst in [false, true]) {
    test(
      'a delayed older catalog cannot supersede the latest search '
      '(latest already completed: $finishLatestFirst)',
      () async {
        final key = Object();
        final older = repository.findBooksAndCategories(
          'אלף',
          category,
          includeOtzar: true,
          includeLocalHebrewBooks: false,
          supersedeKey: key,
        );
        final olderCheck = expectLater(
          older,
          throwsA(isA<BookSearchSupersededException>()),
        );
        await repository.catalogRequested.future;
        if (!finishLatestFirst) {
          // משחררים את הקטלוג בדיוק כשהחיפוש החדש מגיע לתור ה-worker.
          category.onCategories = () => repository.catalog.complete([]);
        }
        final newer = repository.findBooksAndCategories(
          'בית',
          category,
          includeLocalHebrewBooks: false,
          supersedeKey: key,
        );
        final result = await newer;
        expect(result.books.map((book) => book.title), ['מבחן בית']);
        if (finishLatestFirst) repository.catalog.complete([]);
        await olderCheck;
      },
    );
  }
}
