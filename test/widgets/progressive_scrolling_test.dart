import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// מקליט קריאות גלילה במקום להזיז רשימה אמיתית.
class _RecordingScrollOffsetController extends ScrollOffsetController {
  final List<double> offsets = [];

  @override
  Future<void> animateScroll({
    required double offset,
    required Duration duration,
    Curve curve = Curves.linear,
  }) async {
    offsets.add(offset);
  }
}

/// מדמה רשימה מחוברת כדי ש-ProgressiveScroll יסכים לגלול.
class _AttachedItemScrollController extends ItemScrollController {
  @override
  bool get isAttached => true;
}

void main() {
  late _RecordingScrollOffsetController offsetController;
  late FocusNode focusNode;

  Future<void> pumpProgressiveScroll(
    WidgetTester tester, {
    FocusOnKeyEventCallback? onKeyEvent,
    FocusOnKeyEventCallback? onOuterKeyEvent,
  }) async {
    offsetController = _RecordingScrollOffsetController();
    focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          onKeyEvent: onOuterKeyEvent,
          child: ProgressiveScroll(
            onKeyEvent: onKeyEvent,
            scrollController: offsetController,
            itemScrollController: _AttachedItemScrollController(),
            focusNode: focusNode,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
  }

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
    offsetController = _RecordingScrollOffsetController();
    final controller = TextEditingController(text: 'שורה ראשונה\nשורה שנייה');
    final fieldFocus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(fieldFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressiveScroll(
            scrollController: offsetController,
            itemScrollController: _AttachedItemScrollController(),
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
