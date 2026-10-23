import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// פיצול ופירוק מנפישים את מסגרת הכרטיס; אם עובי המסגרת משנה את רוחב
/// התוכן בכל פריים, שני הספרים נפרסים ונבנים מחדש לאורך כל האנימציה.
void main() {
  final contentKey = GlobalKey();
  late List<Size> layouts;

  Widget host({required bool isSplit, bool isActive = true}) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 400,
        height: 300,
        child: PaneCard(
          isActive: isActive,
          isSplit: isSplit,
          child: LayoutBuilder(
            key: contentKey,
            builder: (context, constraints) {
              layouts.add(constraints.biggest);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );

  setUp(() => layouts = []);

  for (final toSplit in [true, false]) {
    testWidgets(
      '${toSplit ? 'פיצול' : 'פירוק'}: התוכן נפרס פעם אחת ולא בכל פריים',
      (tester) async {
        await tester.pumpWidget(host(isSplit: !toSplit));
        layouts.clear();

        await tester.pumpWidget(host(isSplit: toSplit));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(layouts, [
          toSplit ? const Size(398, 298) : const Size(400, 300),
        ]);
      },
    );
  }

  testWidgets('המצב הסופי זהה: תוכן בתוך המסגרת, ומסגרת בצבע החלונית', (
    tester,
  ) async {
    for (final isActive in [true, false]) {
      await tester.pumpWidget(host(isSplit: true, isActive: isActive));
      await tester.pumpAndSettle();

      final card = tester.getRect(find.byType(PaneCard));
      expect(tester.getRect(find.byKey(contentKey)), card.deflate(1));
      final context = tester.element(find.byType(PaneCard));
      final border = _paintedBorder(tester);
      expect(border, isNotNull);
      expect(
        border!.top.color,
        AppSurfaces.paneCardBorder(
          Theme.of(context).colorScheme,
          isActive: isActive,
        ),
      );
      expect(border.dimensions, const EdgeInsets.all(1));
    }

    await tester.pumpWidget(host(isSplit: false));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(contentKey)),
      tester.getRect(find.byType(PaneCard)),
    );
    expect(_paintedBorder(tester), isNull);
  });
}

/// המסגרת שהכרטיס מצייר, בין שהיא ברקע ובין שהיא בחזית.
Border? _paintedBorder(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(PaneCard),
      matching: find.byType(AnimatedContainer),
    ),
  );
  for (final decoration in [
    container.decoration,
    container.foregroundDecoration,
  ]) {
    final border = (decoration as BoxDecoration?)?.border as Border?;
    if (border != null) return border;
  }
  return null;
}
