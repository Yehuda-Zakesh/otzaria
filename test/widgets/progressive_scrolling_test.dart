import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// מקליט קריאות גלילה במקום להזיז רשימה אמיתית.
class _RecordingItemScrollController extends ItemScrollController {
  final _native = _RecordingScrollController();

  List<double> get offsets => _native.recordingPosition.offsets;
  List<double> get directOffsets => _native.recordingPosition.directOffsets;

  // מדמה רשימה מחוברת כדי ש-ProgressiveScroll יסכים לגלול.
  @override
  bool get isAttached => true;

  @override
  ScrollController get scrollController => _native;
}

class _RecordingScrollController extends ScrollController {
  final recordingPosition = _RecordingPosition();

  @override
  ScrollPosition get position => recordingPosition;

  @override
  Iterable<ScrollPosition> get positions => [recordingPosition];
}

class _RecordingPosition extends ChangeNotifier implements ScrollPosition {
  final List<double> offsets = [];
  final List<double> directOffsets = [];

  @override
  double pixels = 100000;

  @override
  double get minScrollExtent => 0;

  @override
  double get maxScrollExtent => 1000000;

  @override
  bool get hasContentDimensions => true;

  @override
  bool get hasPixels => true;

  @override
  void jumpTo(double value) {
    if (pixels == value) return;
    final offset = value - pixels;
    offsets.add(offset);
    directOffsets.add(offset);
    pixels = value;
  }

  @override
  Future<void> animateTo(
    double value, {
    required Duration duration,
    required Curve curve,
  }) async {
    offsets.add(value - pixels);
    pixels = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _RecordingItemScrollController offsetController;
  late FocusNode focusNode;

  Future<void> pumpProgressiveScroll(
    WidgetTester tester, {
    FocusOnKeyEventCallback? onKeyEvent,
    FocusOnKeyEventCallback? onOuterKeyEvent,
    VoidCallback? onNavigationStart,
  }) async {
    offsetController = _RecordingItemScrollController();
    focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          onKeyEvent: onOuterKeyEvent,
          child: ProgressiveScroll(
            onKeyEvent: onKeyEvent,
            scrollController: offsetController,
            focusNode: focusNode,
            onNavigationStart: onNavigationStart,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
  }

  for (final frameMs in [8, 16, 32]) {
    for (final curve in [0.0, 2.0, 10.0]) {
      testWidgets('מרחק גלילה לפי זמן: frame=$frameMs, curve=$curve', (
        tester,
      ) async {
        final item = ItemScrollController();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ProgressiveScroll(
              focusNode: focus,
              scrollController: item,
              maxSpeed: 1000,
              accelerationFactor: 500,
              curve: curve,
              child: ScrollablePositionedList.builder(
                itemScrollController: item,
                itemCount: 10000,
                estimateExtent: (_, width) => 100,
                itemBuilder: (_, index) => SizedBox(
                  height: 100,
                  child: Text('שורה $index'),
                ),
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
        for (var elapsed = 0; elapsed < 160; elapsed += frameMs) {
          await tester.pump(Duration(milliseconds: frameMs));
        }
        final cappedAt = curve == 0 ? double.infinity : math.log(2) / curve;
        final double expected;
        if (curve == 0) {
          expected = 500 * 0.16;
        } else if (cappedAt >= 0.16) {
          expected = 500 * (math.exp(curve * 0.16) - 1) / curve;
        } else {
          expected = 500 / curve + 1000 * (0.16 - cappedAt);
        }
        expect(item.scrollController!.offset, closeTo(expected, 0.01));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(item.scrollController!.offset, closeTo(expected + 100, 0.01));
      });
    }
  }

  testWidgets('רק השחרור מפעיל אנימציה; פריימי הלחיצה נעים ישירות', (
    tester,
  ) async {
    await pumpProgressiveScroll(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(offsetController.directOffsets.length, 10);
    expect(offsetController.offsets, offsetController.directOffsets);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(offsetController.offsets.length, 11);
    expect(offsetController.offsets.last, 100);
  });

  testWidgets('ניווט נרשם פעם להחזקה גם בהאצה והחלפת כיוון', (tester) async {
    var navigations = 0;
    await pumpProgressiveScroll(tester, onNavigationStart: () => navigations++);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    }
    expect(navigations, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 16));
    expect(navigations, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    expect(navigations, 2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });

  for (final noMaximum in [false, true]) {
    testWidgets('מהירות אפס אינה מריצה טיקר או גלישה בשחרור: max=$noMaximum', (
      tester,
    ) async {
      final offset = _RecordingItemScrollController();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProgressiveScroll(
            scrollController: offset,
            focusNode: focus,
            maxSpeed: noMaximum ? 0 : 1000,
            accelerationFactor: noMaximum ? 1000 : 0,
            child: const SizedBox.expand(),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(offset.offsets, isEmpty);
    });
  }

  testWidgets('הוספת Shift בזמן לחיצה עוצרת גם כש-KeyUp מסונן כקיצור', (
    tester,
  ) async {
    await pumpProgressiveScroll(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    expect(offsetController.offsets, isNotEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final count = offsetController.offsets.length;
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    expect(offsetController.offsets.length, count);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('שחרור החץ האחר אינו עוצר את החץ שעדיין לחוץ', (
    tester,
  ) async {
    await pumpProgressiveScroll(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    final count = offsetController.offsets.length;
    await tester.pump(const Duration(milliseconds: 16));
    expect(offsetController.offsets.length, greaterThan(count));
    expect(offsetController.offsets.last, greaterThan(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });

  testWidgets('איבוד חלון עוצר לחיצה בלי לחכות ל-KeyUp', (tester) async {
    await pumpProgressiveScroll(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    expect(offsetController.offsets, isNotEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final count = offsetController.offsets.length;
    await tester.pump(const Duration(seconds: 1));
    expect(offsetController.offsets.length, count);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(offsetController.offsets.length, count);
  });

  testWidgets('חלונית שהוסתרה אינה ממשיכה לחיצה ישנה כשהיא חוזרת', (
    tester,
  ) async {
    offsetController = _RecordingItemScrollController();
    focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, active, child) =>
              TickerMode(enabled: active, child: child!),
          child: ProgressiveScroll(
            scrollController: offsetController,
            focusNode: focusNode,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    enabled.value = false;
    await tester.pump();
    final count = offsetController.offsets.length;
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    enabled.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(offsetController.offsets.length, count);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(offsetController.offsets.length, count);
  });

  testWidgets('החלפת FocusNode מאמצת את החדש בלי לשחרר בקר חיצוני', (
    tester,
  ) async {
    final first = FocusNode();
    final second = FocusNode();
    final offset = _RecordingItemScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget app(FocusNode focus) => MaterialApp(
      home: ProgressiveScroll(
        scrollController: offset,
        focusNode: focus,
        child: const SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(app(first));
    first.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    final count = offset.offsets.length;
    await tester.pumpWidget(app(second));
    second.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(second.hasPrimaryFocus, isTrue);
    expect(first.hasFocus, isFalse);
    expect(offset.offsets.length, count);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    expect(offset.offsets.length, greaterThan(count));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    first.addListener(() {});
    second.addListener(() {});
  });

  testWidgets('החלפת בקר גלילה עוצרת לחיצה בלי להעביר אותה לרשימה אחרת', (
    tester,
  ) async {
    final first = _RecordingItemScrollController();
    final second = _RecordingItemScrollController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget app(ItemScrollController controller) => MaterialApp(
      home: ProgressiveScroll(
        scrollController: controller,
        focusNode: focus,
        child: const SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(app(first));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 16));
    final count = first.offsets.length;
    await tester.pumpWidget(app(second));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    expect(first.offsets.length, count);
    expect(second.offsets, isEmpty);
  });

  for (final isMac in [false, true]) {
    for (final arrow in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ]) {
      testWidgets('קיצור מותאם ${arrow.keyLabel} קודם לגלילה (macOS: $isMac)', (
        tester,
      ) async {
        ShortcutHelper.isMacForTesting = isMac;
        final modifier = isMac
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        addTearDown(() => ShortcutHelper.isMacForTesting = null);
        var activations = 0;
        final bubbled = <KeyEvent>[];
        await pumpProgressiveScroll(
          tester,
          onKeyEvent: (_, event) {
            if (!ShortcutHelper.matchesShortcut(
              event,
              'ctrl+shift+${arrow.keyLabel.toLowerCase().replaceAll(' ', '')}',
            )) {
              return KeyEventResult.ignored;
            }
            activations++;
            return KeyEventResult.handled;
          },
          onOuterKeyEvent: (_, event) {
            bubbled.add(event);
            return KeyEventResult.ignored;
          },
        );
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(arrow);
        await tester.sendKeyRepeatEvent(arrow);
        await tester.sendKeyUpEvent(arrow);
        await tester.pump(const Duration(milliseconds: 200));
        expect(activations, 1);
        expect(
          bubbled.where((e) => e.logicalKey == arrow).map((e) => e.runtimeType),
          [KeyRepeatEvent, KeyUpEvent],
        );
        expect(offsetController.offsets, isEmpty);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(arrow);
        expect(activations, 1, reason: 'צירוף חסר Shift מתבעבע');
        expect(offsetController.offsets, isEmpty);
        await tester.sendKeyUpEvent(modifier);
        await tester.sendKeyDownEvent(arrow);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyRepeatEvent(arrow);
        await tester.sendKeyUpEvent(arrow);
        expect(offsetController.offsets, isNotEmpty);
        expect(
          offsetController.offsets.every(
            (offset) =>
                arrow == LogicalKeyboardKey.arrowDown ? offset > 0 : offset < 0,
          ),
          isTrue,
        );
        final count = offsetController.offsets.length;
        await tester.pump(const Duration(seconds: 1));
        expect(offsetController.offsets.length, count);
      });
    }
  }
  testWidgets('תוצאת skipRemainingHandlers של התוכן נשמרת גם בחץ', (
    tester,
  ) async {
    final bubbled = <KeyEvent>[];
    await pumpProgressiveScroll(
      tester,
      onKeyEvent: (_, _) => KeyEventResult.skipRemainingHandlers,
      onOuterKeyEvent: (_, event) {
        bubbled.add(event);
        return KeyEventResult.ignored;
      },
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(bubbled, isEmpty);
    expect(offsetController.offsets, isEmpty);
  });

  testWidgets('ללא לחיצת מקש — אין שום קריאת גלילה', (tester) async {
    // רגרסיה: בעבר טיימר תמידי רץ כל 16ms גם בלי שום לחיצה.
    await pumpProgressiveScroll(tester);

    await tester.pump(const Duration(seconds: 1));

    expect(offsetController.offsets, isEmpty);
  });

  testWidgets('לחיצת חץ גוללת ושחרור עוצר את הגלילה', (tester) async {
    await pumpProgressiveScroll(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(offsetController.offsets, isNotEmpty);
    expect(offsetController.offsets.every((offset) => offset > 0), isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // שחרור מוסיף גלישה עדינה אחת (glide) של 100 בכיוון הגלילה
    expect(offsetController.offsets.last, 100.0);

    final countAfterRelease = offsetController.offsets.length;
    await tester.pump(const Duration(seconds: 1));
    expect(
      offsetController.offsets.length,
      countAfterRelease,
      reason: 'אחרי שחרור המקש אסור שתימשך גלילה',
    );
  });

  testWidgets('איבוד פוקוס באמצע לחיצה עוצר את הגלילה', (tester) async {
    // הבאג שתוקן: מעבר פוקוס בולע את ה-KeyUp, והגלילה המשיכה לבד לנצח
    // ו"נלחמה" בגלילת המשתמש.
    await pumpProgressiveScroll(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    expect(offsetController.offsets, isNotEmpty);

    focusNode.unfocus();
    await tester.pump();
    final countAfterUnfocus = offsetController.offsets.length;

    await tester.pump(const Duration(seconds: 2));
    expect(
      offsetController.offsets.length,
      countAfterUnfocus,
      reason: 'איבוד פוקוס חייב לעצור את הגלילה גם בלי KeyUp',
    );

    // ניקוי מצב המקלדת של סביבת הטסט (ה-widget כבר לא בפוקוס)
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
  });

  testWidgets('חץ בשדה טקסט שבתוך הרשימה מזיז את הסמן ואינו גולל', (
    tester,
  ) async {
    offsetController = _RecordingItemScrollController();
    final controller = TextEditingController(text: 'שורה ראשונה\nשורה שנייה');
    final fieldFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(fieldFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressiveScroll(
            scrollController: offsetController,
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: TextField(
              controller: controller,
              focusNode: fieldFocus,
              maxLines: null,
            ),
          ),
        ),
      ),
    );
    fieldFocus.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));

    expect(offsetController.offsets, isEmpty);
    expect(controller.selection.baseOffset, greaterThan(0));
  });
}
