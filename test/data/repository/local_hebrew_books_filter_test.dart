import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

import '../../helpers/memory_settings_cache.dart';

/// ספרי היברובוקס שירדו לתיקייה המקומית מצטרפים לאיתור הספר רק כשהמשתמש
/// מבקש זאת (issue #1143) — מי שהגדיר את התיקייה עבור תוסף יכול להסתיר אותם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DataRepository repository;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final category = Category(
      title: 'הלכה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [
        PdfBook(title: 'שולחן ערוך', path: 'shulchan.pdf'),
      ],
      parent: null,
    );
    repository = DataRepository()
      ..library = Future.value(Library(categories: [category]))
      ..localHebrewBooks = Future.value([
        PdfBook(
          title: 'שולחן ערוך היברובוקס',
          path: 'hebrewbooks_org_123.pdf',
          externalLibraryId: 'hebrewbooks',
        ),
      ]);
  });

  test('כברירת מחדל הספרים המקומיים מצטרפים לתוצאות', () async {
    final results = await repository.findBooks(
      'שולחן ערוך',
      null,
      sortByRatio: false,
    );

    expect(results.map((b) => b.title), contains('שולחן ערוך היברובוקס'));
  });

  test('כשההצגה כבויה הספרים המקומיים אינם מצטרפים', () async {
    final results = await repository.findBooks(
      'שולחן ערוך',
      null,
      includeLocalHebrewBooks: false,
      sortByRatio: false,
    );

    expect(results.map((b) => b.title), ['שולחן ערוך']);
  });
}
