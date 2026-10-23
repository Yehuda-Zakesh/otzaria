import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// תצוגה שנייה לבדיקות ריבוי חלונות: עוטפת את [WidgetTester.view] עם מזהה
/// ומסך משלה, כך שגודל ו-DPR נקבעים בנפרד. אינה מציירת דבר.
class SecondTestView extends TestFlutterView {
  SecondTestView(TestFlutterView view, {this.viewId = 100})
    : super(
        view: view,
        platformDispatcher: view.platformDispatcher,
        display: TestDisplay(view.platformDispatcher, view.display),
      );

  @override
  final int viewId;

  @override
  void render(Scene scene, {Size? size}) {}

  @override
  void updateSemantics(SemanticsUpdate update) {}
}
