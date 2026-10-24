import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// המסלול **האמיתי** של העברת כרטיסיה: `toJson` → `jsonEncode` → ארגומנט
/// לנקודת הכניסה → `jsonDecode` → `fromJson`.
///
/// ⚠️ הבדיקות הקיימות בדקו `toJson`→`fromJson` **ישירות**, בלי מעבר
/// ב-JSON — וזה בדיוק הפער שבו באגים חיים. `jsonEncode` דורש פרימיטיבים
/// בלבד, ומפה עם מפתחות שאינם מחרוזת חוזרת ממנו עם מפתחות מחרוזת. טיפוס
/// שעבר את הבדיקה הישירה יכול להיכשל כאן, וזה מה שהמשתמש רואה: חלון חדש
/// נפתח **בלי הכרטיסיה**, כי `decodePayload` בולע את החריגה ומחזיר null.
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  /// עובר את מסלול ההעברה כולו, דרך JSON, כמו [RunnerWindowChannel.canTransfer].
  OpenedTab? throughPayload(OpenedTab tab) =>
      RunnerWindowChannel.transferRoundTrip(tab);

  TextBookTab textTab() =>
      TextBookTab(book: TextBook(title: 'בראשית'), index: 12);

  PdfBookTab pdfTab() => PdfBookTab(
    book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
    pageNumber: 7,
  );

  test('כרטיסיית כלי', () {
    final restored = throughPayload(
      ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה'),
    );
    expect(restored, isA<ToolTab>());
  });

  test('ספר טקסט', () {
    final restored = throughPayload(textTab());
    expect(restored, isA<TextBookTab>());
    expect((restored! as TextBookTab).index, 12);
  });

  test('ספר PDF', () {
    final restored = throughPayload(pdfTab());
    expect(restored, isA<PdfBookTab>());
    expect((restored! as PdfBookTab).pageNumber, 7);
  });

  test('מפרשים על ספר טקסט — "רש״י על בראשית"', () {
    // ⚠️ זה הטיפוס שהמשתמש דיווח עליו: חלון חדש נפתח בלי הכרטיסיה.
    final source = CommentatorsTab(sourceTab: textTab());
    final restored = throughPayload(source);

    expect(
      restored,
      isA<CommentatorsTab>(),
      reason: 'null כאן פירושו שהחלון החדש נפתח ריק',
    );
    expect((restored! as CommentatorsTab).sourceTab.book.title, 'בראשית');
  });

  test('מפרשים על ספר טקסט — עם בחירת מפרשים', () {
    final source = CommentatorsTab(sourceTab: textTab())
      ..selectedCommentators = ['רש"י', 'תוספות'];
    final restored = throughPayload(source) as CommentatorsTab?;
    expect(restored?.selectedCommentators, ['רש"י', 'תוספות']);
  });

  test('מפרשים על ספר PDF', () {
    final restored = throughPayload(PdfCommentatorsTab(sourceTab: pdfTab()));
    expect(restored, isA<PdfCommentatorsTab>());
  });

  test('טאב מפוצל', () {
    final restored = throughPayload(
      CombinedTab(rightTab: textTab(), leftTab: pdfTab()),
    );
    expect(restored, isA<CombinedTab>());
  });

  test('ספר טקסט עם תצורת חיפוש מלאה', () {
    // ⚠️ `alternativeWords` הוא `Map<int, List<String>>`, ומפתחות
    // מספריים חוזרים מ-JSON כמחרוזות. זה המקום המובהק שבו round-trip
    // אמיתי נכשל בעוד הבדיקה הישירה עוברת.
    final tab = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 3,
      searchText: 'אור',
      alternativeWords: {
        0: ['אורה', 'מאור'],
      },
      spacingValues: {'0-1': '2'},
    );
    final restored = throughPayload(tab);
    expect(restored, isA<TextBookTab>());
  });
}
