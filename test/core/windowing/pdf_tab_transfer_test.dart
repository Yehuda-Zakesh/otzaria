import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// כרטיסיית PDF היא המקרה השכיח בספרייה, ו-`canTransfer` היא השער שכל
/// מסלולי ההעברה עוברים דרכו — גרירה ותפריט כאחד. אם היא מחזירה false,
/// הגרירה נעצרת עם הודעה והמשתמש רואה "לא עובד".
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('כרטיסיית PDF ניתנת להעברה בין חלונות', () {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
      pageNumber: 7,
    );
    expect(MultiWindowService.canTransfer(tab), isTrue);
  });

  test('כרטיסיית PDF עם מצב משתמש שורדת את מסלול המטען', () {
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
      pageNumber: 12,
    );
    tab.activeCommentators = {'רש"י'};
    tab.savedZoom = 1.5;
    expect(MultiWindowService.canTransfer(tab), isTrue);
  });

  test('טאב מפוצל שאחת מחלוניותיו PDF ניתן להעברה', () {
    final split = CombinedTab(
      rightTab: PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 1,
      ),
      leftTab: ToolTab(toolId: 'builtin.gematria', title: 'גימטריה'),
    );
    expect(MultiWindowService.canTransfer(split), isTrue);
  });
}
