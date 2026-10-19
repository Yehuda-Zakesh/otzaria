import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // הרוחב הצר הוא הגאומטריה שהפילה את התפריט: אייקון מוביל יחד עם isSelected
  // מאפס את תקציב הלייבל, וה-Spacer שבשורת הפריט מקבל רוחב לא-חסום.
  testWidgets('לחיצה ימנית על אריח ספר פותחת את תפריט בחירת הפורמט', (
    tester,
  ) async {
    final bavli = Category(
      title: 'תלמוד בבלי',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: null,
    );
    final seder = Category(
      title: 'סדר זרעים',
      description: '',
      shortDescription: '',
      order: 0,
      subCategories: [],
      books: [],
      parent: bavli,
    );
    bavli.subCategories.add(seder);
    final book = TextBook(title: 'ברכות', category: seder, categoryId: 10);
    seder.books.add(book);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: AppContextMenuRegion(
                menuBuilder: (_, _) => [
                  AppContextMenuEntry(
                    label: 'פתיחה כטקסט',
                    icon: OtzariaIcons.book_alef_24_regular,
                    onTap: () {},
                  ),
                  AppContextMenuEntry(
                    label: 'פתיחה כ-PDF',
                    icon: OtzariaIcons.book_pdf_24_regular,
                    onTap: () {},
                  ),
                ],
                child: BookGridItem(
                  book: book,
                  onBookClickCallback: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(buttons: kSecondaryButton);
    await gesture.downWithCustomEvent(
      tester.getCenter(find.byType(BookGridItem)),
      PointerDownEvent(
        position: tester.getCenter(find.byType(BookGridItem)),
        buttons: kSecondaryButton,
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('פתיחה כטקסט'), findsOneWidget);
    expect(find.text('פתיחה כ-PDF'), findsOneWidget);
  });
}
