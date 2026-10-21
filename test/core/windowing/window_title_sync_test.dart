import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_title_sync.dart';

/// הכותרת אינה נראית בחלון עצמו (סרגל כותרת מותאם) אלא בשורת המשימות,
/// ב-Alt+Tab ובמנהל המשימות — ושם ארבעה חלונות בשם `אוצריא` הם ארבעה
/// כפתורים זהים שאין דרך להבחין ביניהם.
void main() {
  test('בלי כרטיסיה — שם התוכנה בלבד', () {
    expect(WindowTitleSync.titleFor(null), 'אוצריא');
    expect(WindowTitleSync.titleFor(''), 'אוצריא');
    expect(WindowTitleSync.titleFor('   '), 'אוצריא');
  });

  test('כרטיסיה בודדת — בלי מונה', () {
    // מונה בכרטיסיה בודדת הוא רעש.
    expect(WindowTitleSync.titleFor('בראשית', tabCount: 1), 'בראשית — אוצריא');
  });

  test('כמה כרטיסיות — מונה בסוגריים, כמו בדפדפן', () {
    expect(
      WindowTitleSync.titleFor('בראשית', tabCount: 3),
      'בראשית (3) — אוצריא',
    );
  });

  test('שם התוכנה בסוף ולא בהתחלה', () {
    // ⚠️ שורת המשימות ו-Alt+Tab חותכים כותרות ארוכות **מהסוף**, ולכן מה
    // שמזהה את החלון חייב לבוא ראשון. כותרת שמתחילה ב"אוצריא" הייתה
    // מחזירה בדיוק את הבעיה שהיא באה לפתור.
    final title = WindowTitleSync.titleFor('תלמוד בבלי מסכת ברכות');
    expect(title.startsWith('תלמוד'), isTrue);
    expect(title.endsWith('אוצריא'), isTrue);
  });

  test('כל חלון זוכר רק את הכותרת שנשלחה אליו', () async {
    final sentA = <String>[];
    final sentB = <String>[];
    final a = WindowTitleSync(setTitle: (t) async => sentA.add(t));
    final b = WindowTitleSync(setTitle: (t) async => sentB.add(t));

    await a.sync('בראשית');
    await b.sync('בראשית');
    await a.sync('בראשית');

    expect(sentA, ['בראשית — אוצריא']);
    expect(sentB, ['בראשית — אוצריא']);
  });
}
