import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/dialogs/books_list_dialog.dart';

void main() {
  List<Book> buildBooks(int count) => List.generate(
    count,
    (i) => TextBook(
      title: 'ספר $i',
      author: 'מחבר $i',
      categoryPath: 'קטגוריה $i',
    ),
  );

  Future<void> openDialog(WidgetTester tester, List<Book> books) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showBooksListDialog(context: context, books: books),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('ריחוף מציג שם ופרטים מלאים גם כשהשורה מקוצרת', (tester) async {
    final title = List.filled(14, 'שם ספר ארוך').join(' ');
    final author = List.filled(14, 'שם מחבר ארוך').join(' ');
    await openDialog(tester, [TextBook(title: title, author: author)]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    final details = tester.widget<Text>(find.textContaining(author)).data!;
    for (final text in [title, details]) {
      final label = find.text(text);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isTrue,
      );
      expect(find.byTooltip(text), findsOneWidget);
      await mouse.moveTo(tester.getCenter(label));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(text), findsNWidgets(2));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(text).last)
            .didExceedMaxLines,
        isFalse,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('סינון אחרי קפיצה לסוף מעדכן את תחום הגלילה והתוצאות', (
    tester,
  ) async {
    await openDialog(tester, buildBooks(3000));
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'מחבר 2999');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3000'), findsOneWidget);
    expect(find.text('ספר 2999'), findsOneWidget);
    expect(controller.offset, 0);
    await tester.enterText(find.byType(TextField), 'לא קיים');
    await tester.pumpAndSettle();
    expect(find.text('לא נמצאו ספרים'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('3000 / 3000'), findsOneWidget);
    expect(find.text('ספר 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'פס הגלילה וה-ListView חולקים אותו ScrollController (פס גלילה לחיץ)',
    (tester) async {
      await openDialog(tester, buildBooks(50));

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      final listView = tester.widget<ListView>(find.byType(ListView));

      // שורש התיקון: בלי controller משותף, ה-thumb אינו גריר.
      expect(scrollbar.controller, isNotNull);
      expect(listView.controller, isNotNull);
      expect(scrollbar.controller, same(listView.controller));
      expect(scrollbar.thumbVisibility, isTrue);
    },
  );

  testWidgets('גלילה דרך ה-controller המשותף מזיזה את הרשימה', (tester) async {
    await openDialog(tester, buildBooks(50));

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.offset, 0);

    controller.jumpTo(200);
    await tester.pump();

    expect(controller.offset, 200);
  });

  testWidgets('קפיצה לסוף הרשימה לא בונה את כל השורות שבדרך (#3022)', (
    tester,
  ) async {
    await openDialog(tester, buildBooks(3000));
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;

    var builtRows = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget.runtimeType.toString() == '_BookListRow') builtRows++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // כמו גרירת ה-thumb לסוף: קפיצה רחוקה בפריים אחד.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(builtRows, lessThan(100));
    expect(find.text('ספר 2999'), findsOneWidget);
  });

  testWidgets('הסינון זהה להשוואה נאיבית של כל שדה באותיות קטנות', (
    tester,
  ) async {
    const letters = ['א', 'ב', 'A', 'b', 'Ä', 'ß', 'İ', ' ', '/'];
    final random = Random(3);
    String word() => [
      for (var k = random.nextInt(5); k > 0; k--)
        letters[random.nextInt(letters.length)],
    ].join();
    final books = [
      for (var i = 0; i < 300; i++)
        TextBook(
          title: word(),
          author: random.nextBool() ? word() : null,
          categoryPath: random.nextBool() ? '/${word()}' : null,
        ),
    ];
    await openDialog(tester, books);
    final field = find.byType(TextField);
    for (var n = 0; n < 60; n++) {
      final query = word();
      await tester.enterText(field, query);
      await tester.pump();
      final q = query.trim().toLowerCase();
      final expected = q.isEmpty
          ? books.length
          : books.where((b) {
              final category = (b.categoryPath ?? '').replaceFirst(
                RegExp(r'^/+'),
                '',
              );
              return [
                b.title,
                b.author ?? '',
                category,
                b.fileType ?? '',
              ].any((f) => f.toLowerCase().contains(q));
            }).length;
      expect(
        find.text('$expected / ${books.length}'),
        findsOneWidget,
        reason: query,
      );
    }
  });
}
