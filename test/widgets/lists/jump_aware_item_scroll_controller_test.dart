import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

void main() {
  testWidgets('כל מסלול ניווט מודיע פעם אחת והתיקון השקט אינו מודיע', (
    tester,
  ) async {
    final controller = JumpAwareItemScrollController();
    var notifications = 0;
    controller.addBeforeJumpListener(() => notifications++);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: ScrollablePositionedList.builder(
          itemScrollController: controller,
          itemCount: 1000,
          itemBuilder: (_, index) => SizedBox(
            height: 80,
            child: Text('$index'),
          ),
        ),
      ),
    );
    controller.jumpTo(index: 500);
    await tester.pumpAndSettle();
    expect(notifications, 1);

    final landing = controller.jumpToAsync(index: 700);
    await tester.pumpAndSettle();
    await landing;
    expect(notifications, 2);

    final quietLanding = controller.withoutNotifying(
      () => controller.jumpToAsync(index: 600),
    );
    await tester.pumpAndSettle();
    await quietLanding;
    expect(notifications, 2);

    final animated = controller.scrollTo(
      index: 650,
      duration: const Duration(milliseconds: 100),
      targetRectResolver: (_, box) => Rect.fromLTWH(0, 20, box.size.width, 0),
    );
    await tester.pumpAndSettle();
    await animated;
    expect(notifications, 3);
    await tester.pumpWidget(const SizedBox());
  });
}
