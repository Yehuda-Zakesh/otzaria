import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('מטמון כתובות מופרד לפי קטגוריה וספרייה ומתאפס בין קבצים', () async {
    final dir = Directory.systemTemp.createTempSync('review-import-');
    final db = MyDatabase.withPath('${dir.path}/user.db');
    addTearDown(() async {
      db.close();
      await dir.delete(recursive: true);
    });
    final raw = await db.database;
    raw.execute('PRAGMA foreign_keys=OFF');
    raw.execute(
      "INSERT INTO book(id,categoryId,sourceId,title) VALUES(1,3,1,'ספר'),(2,4,1,'ספר')",
    );
    final calls = <(String, int?, bool, String), int>{};
    final checks = <(String, int?, bool), int>{};
    final csv = StringBuffer(
      'מקור,ספר_מקור,קטגוריית_מקור,מקור_אישי,ספר_יעד,קטגוריית_יעד,יעד_אישי,מיקום_יעד,סוג\n',
    );
    for (var i = 1; i <= 12; i++) {
      csv.writeln(
        '$i,ספר,${i % 2 == 0 ? 3 : 4},לא,ספר,${i % 2 == 0 ? 3 : 4},${i % 3 == 0 ? 'כן' : 'לא'},כתובת,הפניה',
      );
    }
    final result = await UserContentImporter.importContents(
      [
        ImportedFile(name: 'links.csv', content: csv.toString()),
        ImportedFile(name: 'קישורים.csv', content: csv.toString()),
      ],
      db,
      resolveRef:
          ({
            required targetTitle,
            required targetCategoryId,
            required targetIsUserBook,
            required ref,
          }) async {
            final k = (targetTitle, targetCategoryId, targetIsUserBook, ref);
            calls.update(k, (v) => v + 1, ifAbsent: () => 1);
            return 11;
          },
      sourceExists:
          ({required title, required categoryId, required isUserBook}) async {
            final k = (title, categoryId, isUserBook);
            checks.update(k, (v) => v + 1, ifAbsent: () => 1);
            return true;
          },
    );
    expect(result.errors, isEmpty);
    expect(calls.keys.toSet(), {
      ('ספר', 3, false, 'כתובת'),
      ('ספר', 3, true, 'כתובת'),
      ('ספר', 4, false, 'כתובת'),
      ('ספר', 4, true, 'כתובת'),
    });
    expect(calls.values, everyElement(2));
    expect(checks.keys.toSet(), {('ספר', 3, false), ('ספר', 4, false)});
    expect(checks.values, everyElement(2));
    expect(result.linksApplied, 12);
  });
}
