import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/grid_items.dart';

const _long = 'שולחן ערוך אורח חיים עם מפרשים';
const _short = 'בראשית';

Widget _rows(double width, {int generation = 0}) => MaterialApp(
  home: Material(
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SizedBox(
          width: width,
          child: Column(
            // דור שונה = מופעי widget חדשים, כמו בנייה מחדש של הרשימה.
            key: ValueKey(generation),
            children: const [
              LibraryOverflowTooltipText(text: _long, maxLines: 1),
              LibraryOverflowTooltipText(text: _short, maxLines: 1),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('בנייה מחדש באותו רוחב אינה מודדת שוב את הטקסט', (tester) async {
    await tester.pumpWidget(_rows(150));
    final afterFirst = debugLibraryTextOverflowLayouts;
    for (var generation = 1; generation <= 5; generation++) {
      await tester.pumpWidget(_rows(150, generation: generation));
    }
    expect(debugLibraryTextOverflowLayouts, afterFirst);
  });

  testWidgets('Tooltip רק לטקסט שגולש, גם אחרי שינוי רוחב', (tester) async {
    Finder tooltipFor(String text) =>
        find.ancestor(of: find.text(text), matching: find.byType(Tooltip));

    await tester.pumpWidget(_rows(150));
    expect(tooltipFor(_long), findsOneWidget);
    expect(tooltipFor(_short), findsNothing);

    await tester.pumpWidget(_rows(790, generation: 1));
    expect(tooltipFor(_long), findsNothing);

    await tester.pumpWidget(_rows(150, generation: 2));
    expect(tooltipFor(_long), findsOneWidget);
  });

  testWidgets('שינוי בגופני המערכת מודד מחדש', (tester) async {
    await tester.pumpWidget(_rows(150));
    final before = debugLibraryTextOverflowLayouts;
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    await tester.pumpWidget(_rows(150, generation: 1));
    expect(debugLibraryTextOverflowLayouts, greaterThan(before));
  });
}
