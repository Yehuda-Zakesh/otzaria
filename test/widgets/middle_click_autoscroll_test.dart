import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';

const _itemHeight = 40.0;
const _itemCount = 500;
const _viewportHeight = 600.0;

void main() {
  testWidgets('החלפות רבות של רשימות שומרות זיהוי של הרשימה המחוברת בלבד', (
    tester,
  ) async {
    final controllers = <ScrollController>[];
    late StateSetter rebuild;
    var generation = 0;
    var current = ScrollController();
    controllers.add(current);
    addTearDown(() {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MiddleClickAutoScroll(
          child: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return ListView.builder(
                key: ValueKey(generation),
                controller: current,
                itemCount: 100,
                itemBuilder: (_, index) => const SizedBox(height: 100),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 25; i++) {
      final next = ScrollController();
      controllers.add(next);
      rebuild(() {
        generation++;
        current = next;
      });
      await tester.pumpAndSettle();
    }
    expect(
      controllers
          .take(controllers.length - 1)
          .every((item) => !item.hasClients),
      isTrue,
    );
    final center = tester.getCenter(find.byType(ListView));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.down(center);
    await tester.pump();
    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(current.offset, greaterThan(0));
    await gesture.up();
  });

  late ScrollController controller;

  Widget buildApp({
    Widget? child,
    Axis axis = Axis.vertical,
    bool barrier = false,
    int itemCount = _itemCount,
    ScrollPhysics? physics,
    TextDirection direction = TextDirection.ltr,
  }) {
    controller = ScrollController();
    Widget list =
        child ??
        ListView.builder(
          controller: controller,
          scrollDirection: axis,
          physics: physics,
          itemCount: itemCount,
          itemBuilder: (context, index) => SizedBox(
            height: _itemHeight,
            width: _itemHeight,
            child: Text('שורה $index'),
          ),
        );
    if (barrier) list = AutoScrollBarrier(child: list);

    return MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: MiddleClickAutoScroll(
            child: SizedBox(
              height: _viewportHeight,
              width: 400,
              child: list,
            ),
          ),
        ),
      ),
    );
  }

  /// לוחצת על גלגל העכבר ומחזירה את ה-gesture, כדי שאפשר יהיה להזיז ולשחרר.
  Future<TestGesture> middleClick(
    WidgetTester tester,
    Offset position,
  ) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.addPointer(location: position);
    await gesture.down(position);
    await tester.pump();
    return gesture;
  }

  Finder anchor() => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter != null,
    description: 'עוגן הגלילה',
  );

  testWidgets('לחיצת גלגל מציגה עוגן וגוררת גלילה בכיוון התנועה', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    expect(anchor(), findsOneWidget);
    expect(controller.offset, 0.0);

    // מתחת לאזור המת אין תנועה.
    await gesture.moveTo(center + const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, 0.0);

    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    final forward = controller.offset;
    expect(forward, greaterThan(0.0));

    // תנועה למעלה מחזירה אחורה.
    await gesture.moveTo(center - const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, lessThan(forward));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('ככל שמתרחקים מהעוגן הגלילה מהירה יותר', (tester) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.moveTo(center + const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 100));
    final slow = controller.offset;

    await gesture.moveTo(center + const Offset(0, 240));
    await tester.pump(const Duration(milliseconds: 100));
    final fast = controller.offset - slow;

    expect(slow, greaterThan(0.0));
    expect(fast, greaterThan(slow));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('שחרור במקום נועל את הגלילה, ולחיצה נוספת מסיימת', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.up();
    await tester.pump();
    expect(anchor(), findsOneWidget);

    // אחרי השחרור ריחוף העכבר ממשיך להזין את הגלילה.
    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0.0));

    final locked = controller.offset;
    await tester.tapAt(center, buttons: kPrimaryMouseButton);
    await tester.pump(const Duration(milliseconds: 100));
    expect(anchor(), findsNothing);
    expect(controller.offset, locked);
  });

  testWidgets('שחרור אחרי גרירה מסיים את הגלילה', (tester) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    expect(anchor(), findsNothing);
    final stopped = controller.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, stopped);
  });

  testWidgets('Esc מסיים את הגלילה', (tester) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.up();
    await tester.pump();
    expect(anchor(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(anchor(), findsNothing);
  });

  testWidgets('רשימה אופקית נגררת לצדדים בלבד', (tester) async {
    await tester.pumpWidget(buildApp(axis: Axis.horizontal));
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, 0.0);

    await gesture.moveTo(center + const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0.0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('אזור שאינו גליל אינו מפעיל את הגלילה', (tester) async {
    await tester.pumpWidget(
      buildApp(child: const Center(child: Text('אין כאן גלילה'))),
    );

    await middleClick(tester, tester.getCenter(find.text('אין כאן גלילה')));
    expect(anchor(), findsNothing);
  });

  testWidgets('רשימה שתוכנה נכנס במלואו אינה מפעילה את הגלילה', (tester) async {
    await tester.pumpWidget(buildApp(itemCount: 2));

    await middleClick(tester, tester.getCenter(find.byType(ListView)));
    expect(anchor(), findsNothing);
  });

  testWidgets('רשימה עם NeverScrollableScrollPhysics אינה מפעילה', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(physics: const NeverScrollableScrollPhysics()),
    );

    await middleClick(tester, tester.getCenter(find.byType(ListView)));
    expect(anchor(), findsNothing);
  });

  testWidgets('רשימה פנימית שאין בה מה לגלול מוסרת לרשימה החיצונית', (
    tester,
  ) async {
    final outer = ScrollController();
    addTearDown(outer.dispose);

    await tester.pumpWidget(
      buildApp(
        child: ListView(
          controller: outer,
          children: [
            SizedBox(
              height: 200,
              child: ListView(
                key: const Key('inner'),
                children: const [SizedBox(height: 50, child: Text('פנימית'))],
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );

    final center = tester.getCenter(find.text('פנימית'));
    final gesture = await middleClick(tester, center);
    expect(anchor(), findsOneWidget);

    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(outer.offset, greaterThan(0.0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('Shift לחוץ אינו מקפיא את הגלילה', (tester) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    addTearDown(
      () => tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft),
    );

    final gesture = await middleClick(tester, center);
    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0.0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('רשימה אופקית ב-RTL נגררת לכיוון הנכון', (tester) async {
    await tester.pumpWidget(
      buildApp(axis: Axis.horizontal, direction: TextDirection.rtl),
    );
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    // ב-RTL הרשימה מתחילה בימין, ולכן גרירה שמאלה מקדמת אותה.
    await gesture.moveTo(center - const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0.0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets('SmoothWheelScroll אינו מחליק את הגלילה האוטומטית', (
    tester,
  ) async {
    final inner = ScrollController();
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      buildApp(
        child: SmoothWheelScroll(
          child: ListView.builder(
            controller: inner,
            itemCount: _itemCount,
            itemBuilder: (context, index) =>
                SizedBox(height: _itemHeight, child: Text('שורה $index')),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.moveTo(center + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();

    // שחרור אחרי גרירה מסיים מיד — בלי זנב שממשיך לזחול.
    final stopped = inner.offset;
    expect(stopped, greaterThan(0.0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(inner.offset, stopped);
  });

  testWidgets('AutoScrollBarrier שומר את לחיצת הגלגל לשימוש אחר', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(barrier: true));

    await middleClick(tester, tester.getCenter(find.byType(ListView)));
    expect(anchor(), findsNothing);
    expect(controller.offset, 0.0);
  });

  testWidgets('AutoScrollBarrier על פריט בתוך רשימה גלילה חוסם', (
    tester,
  ) async {
    final inner = ScrollController();
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      buildApp(
        child: ListView.builder(
          controller: inner,
          itemCount: _itemCount,
          itemBuilder: (context, index) => SizedBox(
            height: _itemHeight,
            child: AutoScrollBarrier(child: Text('שורה $index')),
          ),
        ),
      ),
    );

    await middleClick(tester, tester.getCenter(find.text('שורה 3')));
    expect(anchor(), findsNothing);
    expect(inner.offset, 0.0);
  });

  testWidgets('מעבר לרקע מסיים את הגלילה', (tester) async {
    await tester.pumpWidget(buildApp());

    final gesture = await middleClick(
      tester,
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.up();
    await tester.pump();
    expect(anchor(), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(anchor(), findsNothing);
  });

  testWidgets('לחיצת גלגל במגע אינה מפעילה את הגלילה', (tester) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.touch,
      buttons: kMiddleMouseButton,
    );
    await gesture.down(center);
    await tester.pump();

    expect(anchor(), findsNothing);
    await gesture.up();
  });

  testWidgets('פירוק הווידג׳ט בזמן גלילה נעולה אינו זורק', (tester) async {
    await tester.pumpWidget(buildApp());

    final gesture = await middleClick(
      tester,
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.up();
    await tester.pump();
    expect(anchor(), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('כשהרשימה יורדת מהמסך הגלילה מסתיימת', (tester) async {
    await tester.pumpWidget(buildApp());
    final center = tester.getCenter(find.byType(ListView));

    final gesture = await middleClick(tester, center);
    await gesture.up();
    await tester.pump();
    expect(anchor(), findsOneWidget);

    await tester.pumpWidget(
      buildApp(child: const Center(child: Text('מסך אחר'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(anchor(), findsNothing);
  });
}
