import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';

/// חלונית החיפוש בספר נבנית גם לפני שההעדפות אותחלו (טסטי ווידג'ט, אתחול
/// מוקדם). הקובץ הזה מריץ בכוונה בלי `Settings.init`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('הקובץ אכן רץ בלי אתחול ההעדפות', () {
    expect(Settings.isInitialized, isFalse);
  });

  test('ברירת המחדל היא התאמה חלקית (issue #1046)', () {
    expect(InBookSearchPreferences.loadWholeWord(), isFalse);
  });

  test('שמירה בלי אתחול אינה זורקת — גם לא אסינכרונית', () async {
    await expectLater(
      InBookSearchPreferences.saveWholeWord(true),
      completes,
    );
    // הכשל נבלע ולכן ההעדפה נשארת בברירת המחדל, בלי לקרוס.
    expect(InBookSearchPreferences.loadWholeWord(), isFalse);
  });

  test('מסלול המנוע תמיד מילים שלמות, ללא תלות בהעדפה', () {
    expect(
      InBookSearchPreferences.resolveWholeWord(isSimpleSearch: false),
      isTrue,
    );
    expect(
      InBookSearchPreferences.resolveWholeWord(isSimpleSearch: true),
      isFalse,
    );
  });
}
