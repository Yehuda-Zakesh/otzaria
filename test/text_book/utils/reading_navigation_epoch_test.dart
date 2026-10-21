import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ניווט מפורש מודיע פעם אחת ולפני שמיקום היעד מתפרסם', () async {
    final lines = LineScrollController();
    addTearDown(lines.dispose);
    final previousLines = <int?>[];
    lines.navigationEpoch.addListener(
      () => previousLines.add(lines.position.value?.topLine),
    );
    await lines.jumpToLine(10);
    await lines.scrollToLine(20);
    lines.scrollToLineOnNextAttach(30);
    expect(lines.navigationEpoch.value, 3);
    expect(previousLines, [null, 10, 20]);
    expect(lines.position.value!.topLine, 30);
  });

  test('דיווח מקורא חיצוני ותיקון פריסה אינם ניווט חדש', () {
    final lines = LineScrollController();
    addTearDown(lines.dispose);
    lines.reportExternalLine(10);
    lines.keepViewAcrossRelayout();
    expect(lines.navigationEpoch.value, 0);
    expect(lines.position.value!.topLine, 10);
  });
}
