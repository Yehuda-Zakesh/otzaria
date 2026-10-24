import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/repository/bookmark_repository.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/models/books.dart';

/// **הבדיקה שמגנה על 99% מהמשתמשים.**
///
/// שכבת מצב המשתמש המשותף נוספה עבור ריבוי חלונות, אבל היא יושבת על מסלול
/// הכתיבה של **כל** משתמש — כולל מי שלעולם לא יפתח חלון שני. שתי דרישות:
///
/// 1. **אפס המתנה.** אין מסלול שבו שמירת סימנייה ממתינה ל-timeout.
/// 2. **אפס שינוי התנהגות.** הוספה, הסרה ומחיקה עובדות בדיוק כמו קודם,
///    מול מסד אמיתי.
void main() {
  Bookmark bookmark(String title, {int index = 0}) => Bookmark(
    ref: title,
    book: TextBook(title: title),
    index: index,
  );

  late Directory tmp;
  late UserStateDatabase database;
  late UserStateListStore store;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_single_window_');
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    store = UserStateListStore(database: database);
  });

  tearDown(() async {
    database.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('[יחיד] היסטוריה: הוספה, קריאה והסרה, בלי המתנה', () async {
    final repo = HistoryRepository(store: store);
    final started = DateTime.now();

    await repo.mutateHistory((current) => [bookmark('בראשית'), ...current]);
    await repo.mutateHistory((current) => [bookmark('שמות'), ...current]);

    expect((await repo.loadHistory()).map((b) => b.book.title), [
      'שמות',
      'בראשית',
    ]);

    await repo.mutateHistory(
      (current) => current.where((b) => b.book.title != 'שמות').toList(),
    );
    expect((await repo.loadHistory()).map((b) => b.book.title), ['בראשית']);

    // ⚠️ המספר הוא הראיה שלא הומתן לשום timeout.
    final elapsed = DateTime.now().difference(started);
    expect(elapsed.inMilliseconds, lessThan(500));
  });

  test('[יחיד] סימניות: הוספה ומחיקה נשמרות למסד האמיתי', () async {
    final repo = BookmarkRepository(store: store);

    await repo.mutateBookmarks((current) => [...current, bookmark('ויקרא')]);
    await repo.mutateBookmarks(
      (current) => [...current, bookmark('במדבר', index: 4)],
    );

    // נקרא מהמסד עצמו, כלומר מה שבאמת נכתב.
    expect(await store.read('bookmarks', 'key-bookmarks'), hasLength(2));

    await repo.clearBookmarks();
    expect(await repo.loadBookmarks(), isEmpty);
  });

  test('רשומה פגומה מדולגת בתצוגה ואינה נמחקת בכתיבה', () async {
    // ⚠️ מחיקת נתונים בגלל באג פענוח היא בדיוק מה שאסור. הרשומה אינה
    // מוצגת, אבל היא נשארת על הדיסק לניסיון הבא או לתיקון.
    await store.write('history', 'history', [
      {'this': 'is not a bookmark'},
      bookmark('דברים').toJson(),
    ]);
    final repo = HistoryRepository(store: store);

    expect((await repo.loadHistory()).map((b) => b.book.title), ['דברים']);

    await repo.mutateHistory((current) => [bookmark('יהושע'), ...current]);

    final stored = await store.read('history', 'history');
    expect(stored, hasLength(3));
    expect(
      stored.any((e) => e is Map && e['this'] == 'is not a bookmark'),
      isTrue,
    );
  });

  test('כשל כתיבה מתפשט ואינו נבלע', () async {
    // ⚠️ שלוש שכבות תלויות בכשל הזה: ההודעה למשתמש, הניסיון החוזר
    // ב-PreCloseRegistry, ודיווח ל-Sentry.
    database.close();
    final broken = UserStateDatabase.openAt('${tmp.path}/missing/dir/x.db');
    await expectLater(
      UserStateListStore(
        database: broken,
      ).write('history', 'history', const []),
      throwsA(anything),
    );
  });
}
