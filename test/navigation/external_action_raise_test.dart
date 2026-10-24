import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';

void main() {
  const newWindow = OpenNewWindowAction();
  const other = OpenInspectionAction();

  test('חלון חדש כשאפשר לפתוח חלונות: לא מעלים חלון קיים', () {
    expect(
      externalActionRaisesWindow(newWindow, canOpenWindows: true),
      isFalse,
    );
  });

  test('חלון חדש בחלון יחיד: מציגים ומעלים את הראשי', () {
    expect(
      externalActionRaisesWindow(newWindow, canOpenWindows: false),
      isTrue,
    );
  });

  test('קישור אחר מעלה את החלון בכל מצב', () {
    expect(externalActionRaisesWindow(other, canOpenWindows: true), isTrue);
    expect(externalActionRaisesWindow(other, canOpenWindows: false), isTrue);
  });
}
