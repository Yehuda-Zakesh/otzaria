import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/selection/enhanced_gesture_detector.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ScrollController scroll,
    List<String> taps, {
    List<String>? doubles,
    double topPadding = 0,
    Object? group,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Listener(
        onPointerDown: (event) {
          if (group != null) {
            EnhancedGestureDetector.cancelPendingTap(
              group,
              exceptPointer: event.pointer,
            );
          }
        },
        onPointerSignal: (_) {
          if (group != null) EnhancedGestureDetector.cancelPendingTap(group);
        },
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.only(top: topPadding),
          children: [
            for (final name in ['A', 'B'])
              EnhancedGestureDetector(
                key: ValueKey(name),
                coordinationGroup: group,
                onSingleTap: () => taps.add(name),
                onDoubleTap: () => doubles?.add(name),
                child: SizedBox(height: 200, child: Text(name)),
              ),
            const SizedBox(height: 1000),
          ],
        ),
      ),
    ),
  );

  testWidgets('single tap runs once after the multiple tap window', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final taps = <String>[];
    await pump(tester, scroll, taps);
    await tester.tap(find.byKey(const ValueKey('A')));
    await tester.pump(const Duration(milliseconds: 299));
    expect(taps, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    expect(taps, ['A']);
  });

  for (final wheel in [false, true]) {
    testWidgets('scroll cancels a pending single tap, wheel=$wheel', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final taps = <String>[];
      await pump(tester, scroll, taps);
      await tester.tap(find.byKey(const ValueKey('A')));
      await tester.pump(const Duration(milliseconds: 100));
      if (wheel) {
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(100, 50),
            scrollDelta: Offset(0, 120),
          ),
        );
      } else {
        scroll.jumpTo(120);
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(taps, isEmpty);
    });
  }

  testWidgets('a newer paragraph tap cancels the previous pending tap', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final taps = <String>[];
    await pump(tester, scroll, taps);
    await tester.tap(find.byKey(const ValueKey('A')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('B')));
    await tester.pump(const Duration(milliseconds: 301));
    expect(taps, ['B']);
  });

  testWidgets(
    'a silent pixel correction preserving the visible item keeps the tap',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final taps = <String>[];
      await pump(tester, scroll, taps);
      await tester.tap(find.byKey(const ValueKey('A')));
      scroll.position.correctPixels(120);
      await tester.pump(const Duration(milliseconds: 301));
      expect(taps, ['A']);
    },
  );

  testWidgets('a silent visual relocation invalidates the pending tap', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final taps = <String>[];
    await pump(tester, scroll, taps);
    await tester.tap(find.byKey(const ValueKey('A')));
    await tester.pump(const Duration(milliseconds: 100));
    await pump(tester, scroll, taps, topPadding: 80);
    await tester.pump(const Duration(milliseconds: 301));
    expect(taps, isEmpty);
  });

  for (final scoped in [false, true]) {
    for (final triple in [false, true]) {
      testWidgets(
        'multiple tap preserves selection, triple=$triple scoped=$scoped',
        (
          tester,
        ) async {
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          final taps = <String>[];
          final doubles = <String>[];
          await pump(
            tester,
            scroll,
            taps,
            doubles: doubles,
            group: scoped ? Object() : null,
          );
          await tester.tap(find.byKey(const ValueKey('A')));
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tap(find.byKey(const ValueKey('A')));
          if (triple) {
            await tester.pump(const Duration(milliseconds: 80));
            await tester.tap(find.byKey(const ValueKey('A')));
          }
          await tester.pump(const Duration(milliseconds: 500));
          expect(taps, isEmpty);
          expect(doubles, ['A']);
        },
      );
    }
  }

  testWidgets('disposing a pending tap removes its callback and listeners', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final taps = <String>[];
    await pump(tester, scroll, taps);
    await tester.tap(find.byKey(const ValueKey('A')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpScopes(WidgetTester tester, List<String> taps) {
    Widget scope(String name, Object group) => Listener(
      onPointerDown: (event) => EnhancedGestureDetector.cancelPendingTap(
        group,
        exceptPointer: event.pointer,
      ),
      onPointerSignal: (_) => EnhancedGestureDetector.cancelPendingTap(group),
      child: Column(
        children: [
          EnhancedGestureDetector(
            key: ValueKey('source-$name'),
            coordinationGroup: group,
            onSingleTap: () => taps.add(name),
            child: SizedBox(height: 100, child: Text('source-$name')),
          ),
          Expanded(
            child: ListView(
              children: [
                TextButton(
                  key: ValueKey('button-$name'),
                  onPressed: () => taps.add('button-$name'),
                  child: Text('button-$name'),
                ),
                EnhancedGestureDetector(
                  key: ValueKey('nested-$name'),
                  coordinationGroup: group,
                  onSingleTap: () => taps.add('nested-$name'),
                  child: SizedBox(height: 100, child: Text('nested-$name')),
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ],
      ),
    );
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(child: scope('A', Object())),
              Expanded(child: scope('B', Object())),
            ],
          ),
        ),
      ),
    );
  }

  for (final target in ['button', 'nested', 'wheel']) {
    testWidgets('nested $target cancels the source tap in its reader', (
      tester,
    ) async {
      final taps = <String>[];
      await pumpScopes(tester, taps);
      await tester.tap(find.byKey(const ValueKey('source-A')));
      await tester.pump(const Duration(milliseconds: 80));
      if (target == 'wheel') {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byKey(const ValueKey('nested-A'))),
            scrollDelta: const Offset(0, 100),
          ),
        );
      } else {
        await tester.tap(find.byKey(ValueKey('$target-A')));
      }
      await tester.pump(const Duration(milliseconds: 301));
      expect(taps, target == 'wheel' ? isEmpty : ['$target-A']);
    });
  }

  testWidgets('separate reader scopes do not cancel each other', (
    tester,
  ) async {
    final taps = <String>[];
    await pumpScopes(tester, taps);
    await tester.tap(find.byKey(const ValueKey('source-A')));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(const ValueKey('source-B')));
    await tester.pump(const Duration(milliseconds: 301));
    expect(taps, ['A', 'B']);
  });

  testWidgets('replacing the coordination group cancels an old callback', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final taps = <String>[];
    await pump(tester, scroll, taps, group: Object());
    final state = tester.state(find.byKey(const ValueKey('A')));
    await tester.tap(find.byKey(const ValueKey('A')));
    await tester.pump(const Duration(milliseconds: 80));
    await pump(tester, scroll, taps, group: Object());
    expect(tester.state(find.byKey(const ValueKey('A'))), same(state));
    await tester.pump(const Duration(milliseconds: 301));
    expect(taps, isEmpty);
  });

  testWidgets('middle click remains available for automatic scrolling', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final taps = <String>[];
    await pump(tester, scroll, taps);
    await tester.tap(
      find.byKey(const ValueKey('A')),
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, isEmpty);
  });
}
