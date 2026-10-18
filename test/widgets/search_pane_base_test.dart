import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  testWidgets('בתוך חלונית ניווט השדה והפעולות שלו מצוירים בחלונית עצמה', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final host = NavPanelSearchHost();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
      host.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavPanelSearchScope(
            host: host,
            child: NavPanelSearchSlot(
              index: 0,
              child: SearchPaneBase(
                searchController: controller,
                focusNode: focusNode,
                resultsWidget: const SizedBox.shrink(),
                isNoResults: false,
                resetSearchCallback: () {},
                searchFieldActions: const [
                  Icon(Icons.abc, key: ValueKey('wholeWordToggle')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(RtlTextField), findsOneWidget);
    expect(find.byKey(const ValueKey('wholeWordToggle')), findsOneWidget);
  });

  testWidgets('searchFieldActions מוצגות גם בשדה המקומי (מחוץ לחלונית)', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPaneBase(
            searchController: controller,
            focusNode: focusNode,
            resultsWidget: const SizedBox.shrink(),
            isNoResults: false,
            resetSearchCallback: () {},
            searchFieldActions: const [
              Icon(Icons.abc, key: ValueKey('wholeWordToggle')),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('wholeWordToggle')), findsOneWidget);
  });

  testWidgets('מציג toolbar של תוצאות באותה שורה מול מונה התוצאות', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'נחל');
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPaneBase(
            searchController: controller,
            focusNode: focusNode,
            resultToolbar: const Text(
              '1 מתוך 4',
              textDirection: TextDirection.rtl,
            ),
            resultCountString: 'נמצאו 4 תוצאות',
            resultsWidget: const SizedBox.shrink(),
            isNoResults: false,
            resetSearchCallback: () {},
          ),
        ),
      ),
    );

    final toolbarFinder = find.text('1 מתוך 4');
    final counterFinder = find.text('נמצאו 4 תוצאות');

    expect(toolbarFinder, findsOneWidget);
    expect(counterFinder, findsOneWidget);
    final toolbarRect = tester.getRect(toolbarFinder);
    final counterRect = tester.getRect(counterFinder);

    expect(
      (toolbarRect.center.dy - counterRect.center.dy).abs(),
      lessThan(4),
    );
    expect(toolbarRect.left, greaterThan(counterRect.left));
  });

  testWidgets('צובע את אזור התוצאות ב-Material שקוף כך שהדגשת הכרטיסייה הפעילה '
      'לא דולפת אליו ולא לשדה החיפוש', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    const resultsKey = ValueKey('resultsContent');
    const tabHighlightColor = Colors.orange;

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // מדמה כרטיסייה פעילה עם צבע הדגשה מסביב לפאנל
          body: Material(
            color: tabHighlightColor,
            child: SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              resultsWidget: const SizedBox(key: resultsKey),
              isNoResults: false,
              resetSearchCallback: () {},
            ),
          ),
        ),
      ),
    );

    final nearestMaterial = tester.widget<Material>(
      find
          .ancestor(of: find.byKey(resultsKey), matching: find.byType(Material))
          .first,
    );
    expect(nearestMaterial.color, Colors.transparent);

    final searchFieldDecoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration;
    expect(searchFieldDecoration?.fillColor, isNot(tabHighlightColor));
  });

  testWidgets('כאשר יש errorMessage מוצגת הודעת השגיאה ולא "אין תוצאות"', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'נחל');
    final focusNode = FocusNode();

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPaneBase(
            searchController: controller,
            focusNode: focusNode,
            resultsWidget: const SizedBox.shrink(),
            isNoResults: true,
            errorMessage: 'שגיאה בחיפוש',
            resetSearchCallback: () {},
          ),
        ),
      ),
    );

    expect(find.text('שגיאה בחיפוש'), findsOneWidget);
    expect(find.text('אין תוצאות'), findsNothing);
  });

  testWidgets(
    'ללא errorMessage ועם isNoResults מוצגת ההודעה הגנרית "אין תוצאות"',
    (tester) async {
      final controller = TextEditingController(text: 'נחל');
      final focusNode = FocusNode();

      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              resultsWidget: const SizedBox.shrink(),
              isNoResults: true,
              resetSearchCallback: () {},
            ),
          ),
        ),
      );

      expect(find.text('אין תוצאות'), findsOneWidget);
    },
  );

  testWidgets('בחלונית מרחפת Esc ראשון מנקה את השדה והשני סוגר אותה', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var resets = 0;
    var closed = 0;

    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSidePane(
            isOpen: true,
            floatOverContent: true,
            onClose: () => closed++,
            mainContent: const SizedBox.expand(),
            paneContent: SearchPaneBase(
              searchController: controller,
              focusNode: focusNode,
              resultsWidget: const SizedBox.shrink(),
              isNoResults: false,
              resetSearchCallback: () => resets++,
            ),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(RtlTextField), 'בראשית');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(controller.text, isEmpty);
    expect(resets, 1);
    expect(closed, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 1);
    expect(focusNode.hasFocus, isFalse, reason: 'הקלדה לא תיכנס לשדה נסתר');
  });
}
