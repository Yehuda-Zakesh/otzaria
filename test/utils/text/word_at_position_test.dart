import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/word_at_position.dart';

import '../../test_helpers/second_test_view.dart';

void main() {
  Widget word(String text) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: Text(text)),
  );

  testWidgets('עם תצוגה — רק המילה שבתצוגה הזו', (tester) async {
    final second = SecondTestView(tester.view);
    await tester.pumpWidget(
      wrapWithView: false,
      ViewCollection(
        views: [
          View(view: tester.view, child: word('alpha')),
          View(view: second, child: word('beta')),
        ],
      ),
    );
    const point = Offset(5, 5);

    expect(wordAtGlobalPosition(point, view: tester.view), 'alpha');
    expect(wordAtGlobalPosition(point, view: second), 'beta');
  });

  testWidgets('בלי תצוגה — כמו קודם, בתצוגה היחידה', (tester) async {
    await tester.pumpWidget(word('alpha'));
    expect(wordAtGlobalPosition(const Offset(5, 5)), 'alpha');
  });
}
