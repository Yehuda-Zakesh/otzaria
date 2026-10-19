// בדיקות למפרשים קבועים לקטגוריה (issue #866): שמירה בשמות בסיסיים,
// טעינה לפי שרשרת הקטגוריות מהספציפית לכללית, קביעה ריקה מפורשת והסרה.

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/category_commentators_service.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  test('שמירה וטעינה — השמות נשמרים בסיסיים בלי שם הספר', () async {
    await CategoryCommentatorsService.save(
      'תלמוד בבלי',
      ['רש"י על ברכות', 'תוספות על ברכות', 'יכין מקואות'],
      bookTitle: 'ברכות',
    );

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      ['רש"י', 'תוספות', 'יכין מקואות'],
    );
  });

  test('כפילויות בשם הבסיסי מאוחדות', () async {
    await CategoryCommentatorsService.save(
      'תלמוד בבלי',
      ['רש"י על ברכות', 'רש"י על שבת'],
      bookTitle: 'ברכות',
    );

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      ['רש"י'],
    );
  });

  test('הסריקה מעדיפה את הקטגוריה הספציפית ביותר', () async {
    await CategoryCommentatorsService.save(
      'משנה תורה',
      ['כסף משנה'],
      bookTitle: 'משנה תורה',
    );
    await CategoryCommentatorsService.save(
      'ספר מדע',
      ['לחם משנה'],
      bookTitle: 'משנה תורה',
    );

    expect(
      CategoryCommentatorsService.loadBaseNames('הלכה, משנה תורה, ספר מדע'),
      ['לחם משנה'],
    );
  });

  test('בלי קביעה — מוחזר null (נופלים לברירת המחדל מה-DB)', () {
    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      isNull,
    );
    expect(CategoryCommentatorsService.loadBaseNames(null), isNull);
  });

  test('קביעה ריקה מפורשת מוחזרת כרשימה ריקה, לא כ-null', () async {
    await CategoryCommentatorsService.save(
      'תלמוד בבלי',
      const [],
      bookTitle: 'ברכות',
    );

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      isEmpty,
    );
  });

  test('reset מסיר את הקביעה', () async {
    await CategoryCommentatorsService.save(
      'תלמוד בבלי',
      ['רש"י על ברכות'],
      bookTitle: 'ברכות',
    );
    await CategoryCommentatorsService.reset('תלמוד בבלי');

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תלמוד, תלמוד בבלי'),
      isNull,
    );
    expect(
      CategoryCommentatorsService.hasCategorySettings('תלמוד בבלי'),
      isFalse,
    );
  });

  test('getActiveCategory מחזיר את הקטגוריה שממנה תיטען הקביעה', () async {
    await CategoryCommentatorsService.save(
      'משנה תורה',
      ['כסף משנה'],
      bookTitle: 'משנה תורה',
    );

    expect(
      CategoryCommentatorsService.getActiveCategory(
        'הלכה, משנה תורה, ספר מדע',
      ),
      'משנה תורה',
    );
    expect(
      CategoryCommentatorsService.getActiveCategory('אוצריא, תנ"ך, תורה'),
      isNull,
    );
  });

  test('קביעה לקטגוריה של ספר אחד לא דולפת לספר מענף אחר', () async {
    await CategoryCommentatorsService.save(
      'תורה',
      ['רש"י על בראשית'],
      bookTitle: 'בראשית',
    );

    expect(
      CategoryCommentatorsService.loadBaseNames('אוצריא, תנ"ך, תורה, בראשית'),
      ['רש"י'],
    );
    expect(
      CategoryCommentatorsService.loadBaseNames(
        'אוצריא, תנ"ך, נביאים, ישעיהו',
      ),
      isNull,
    );
  });
}
