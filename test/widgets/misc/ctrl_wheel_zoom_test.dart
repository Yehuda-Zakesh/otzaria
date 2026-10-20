import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/ctrl_wheel_zoom.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:otzaria/widgets/misc/smooth_wheel_scroll.dart';

void main() {
  late List<bool> zooms;
  late ScrollController scroll;

  Future<void> pumpZoom(
    WidgetTester tester, {
    bool autoScroll = false,
  }) async {
    zooms = [];
    scroll = ScrollController(initialScrollOffset: 500);
    addTearDown(scroll.dispose);
    Widget list = ListView.builder(
      controller: scroll,
      itemCount: 100,
      itemBuilder: (_, i) => SizedBox(height: 50, child: Text('שורה $i')),
    );
    if (autoScroll) list = SmoothWheelScroll(child: list);
    Widget viewer = CtrlWheelZoom(onZoom: zooms.add, child: list);
    if (autoScroll) viewer = MiddleClickAutoScroll(child: viewer);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: viewer)));
  }

  Future<void> wheel(
    WidgetTester tester,
    double dy, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final pointer = TestPointer(1, kind);
    pointer.hover(tester.getCenter(find.byType(ListView)));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets('Ctrl + wheel zooms instead of scrolling', (tester) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    await wheel(tester, -100);
    await wheel(tester, 100);

    expect(zooms, [true, false]);
    expect(scroll.offset, 500);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('a notch of one line still makes one step', (tester) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    await wheel(tester, -100 / 3);

    expect(zooms, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('small pinch deltas add up to a step', (tester) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

    for (var i = 0; i < 2; i++) {
      await wheel(tester, -10);
    }
    expect(zooms, isEmpty);
    await wheel(tester, -10);

    expect(zooms, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('the wheel without Ctrl scrolls as before', (tester) async {
    await pumpZoom(tester);

    await wheel(tester, 100);

    expect(zooms, isEmpty);
    expect(scroll.offset, 600);
  });

  testWidgets('Ctrl + Shift + wheel is left to the scrollable', (
    tester,
  ) async {
    await pumpZoom(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

    await wheel(tester, -100);

    expect(zooms, isEmpty);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets(
    'Ctrl does not turn middle-click autoscroll into zoom',
    (
      tester,
    ) async {
      await pumpZoom(tester, autoScroll: true);
      final center = tester.getCenter(find.byType(ListView));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await tester.pump();
      await gesture.moveTo(center + const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset, greaterThan(500));

      final beforeCtrl = scroll.offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
      final afterCtrl = scroll.offset;
      await gesture.up();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(zooms, isEmpty);
      expect(afterCtrl, greaterThan(beforeCtrl));
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset, afterCtrl);
    },
  );
}
