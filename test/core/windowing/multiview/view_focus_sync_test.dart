import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/view_focus_sync.dart';

class _FocusEvents with WidgetsBindingObserver {
  final List<ViewFocusEvent> events = [];

  @override
  void didChangeViewFocus(ViewFocusEvent event) => events.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FocusEvents observer;

  setUp(() {
    observer = _FocusEvents();
    WidgetsBinding.instance.addObserver(observer);
  });

  tearDown(() {
    WidgetsBinding.instance.removeObserver(observer);
    ViewFocusSync.resetForTest();
  });

  test('הפעלת חלון שולחת ViewFocusEvent לתצוגה שלו, פעם אחת למעבר', () {
    ViewFocusSync.debugEnabledOverride = true;

    ViewFocusSync.windowActivated(7);
    ViewFocusSync.windowActivated(7);
    ViewFocusSync.mainWindowActivated();
    ViewFocusSync.windowActivated(7);

    final implicitId =
        WidgetsBinding.instance.platformDispatcher.implicitView!.viewId;
    expect(observer.events.map((e) => e.viewId), [7, implicitId, 7]);
    expect(
      observer.events.every(
        (e) =>
            e.state == ViewFocusState.focused &&
            e.direction == ViewFocusDirection.undefined,
      ),
      isTrue,
    );
  });

  test('כבוי (Windows/macOS, או בלי ריבוי תצוגות): אין אירוע', () {
    ViewFocusSync.debugEnabledOverride = false;
    ViewFocusSync.windowActivated(7);
    ViewFocusSync.mainWindowActivated();
    expect(observer.events, isEmpty);
  });

  test('macOS: חלון שנחשף מקבל אירוע פוקוס ראשון; בשאר הפלטפורמות לא', () {
    ViewFocusSync.debugMacOSOverride = false;
    ViewFocusSync.viewWindowRevealed(9);
    expect(observer.events, isEmpty);

    ViewFocusSync.debugMacOSOverride = true;
    ViewFocusSync.viewWindowRevealed(9);
    expect(observer.events.single.viewId, 9);
    expect(observer.events.single.state, ViewFocusState.focused);
  });
}
