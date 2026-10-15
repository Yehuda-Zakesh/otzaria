import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('Escape closes one nested submenu at a time in $direction', (
      tester,
    ) async {
      final key = GlobalKey<AppContextMenuRegionState>();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Focus(
                focusNode: focus,
                autofocus: true,
                child: AppContextMenuRegion(
                  key: key,
                  menuBuilder: (_, _) => [
                    AppContextMenuEntry(
                      label: 'ראשי',
                      childrenBuilder: () => [
                        AppContextMenuEntry(
                          label: 'פנימי',
                          childrenBuilder: () => [
                            AppContextMenuEntry(
                              label: 'נוסף',
                              childrenBuilder: () => [
                                AppContextMenuEntry(
                                  label: selected ? 'נבחר' : 'פעולה',
                                  keepOpen: true,
                                  onTap: () => selected = !selected,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.openMenuAt(const Offset(50, 50));
      await tester.pumpAndSettle();
      for (final label in ['ראשי', 'פנימי', 'נוסף']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('פעולה'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.text('נבחר'), findsOneWidget);
      expect(focus.hasPrimaryFocus, isTrue);

      for (final label in ['נבחר', 'נוסף', 'פנימי']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text(label), findsNothing);
        expect(find.text('ראשי'), findsOneWidget);
        expect(focus.hasPrimaryFocus, isTrue);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('ראשי'), findsNothing);
      expect(focus.hasPrimaryFocus, isTrue);
    });
  }
}
