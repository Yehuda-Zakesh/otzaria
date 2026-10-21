import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/text_book/view/widgets/nav_panel_tour_target.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

/// שני חלונות באותו עץ מסמנים את אותו יעד סיור בלי Duplicate GlobalKey.
void main() {
  testWidgets('כל scope פותר יעדי סיור משלו', (tester) async {
    final window = _FakeWindow();
    final a = AppWindowKeys();
    final b = AppWindowKeys();

    Widget target(AppWindowKeys keys) => AppWindowScope(
      controller: window,
      geometry: window,
      keys: keys,
      child: Builder(
        builder: (context) => SizedBox(
          key: TourTargetKeys.of(context).readingScreen,
          width: 10,
          height: 10,
        ),
      ),
    );

    await tester.pumpWidget(Column(children: [target(a), target(b)]));

    expect(tester.takeException(), isNull);
    expect(a.tour.readingScreen.currentContext, isNotNull);
    expect(b.tour.readingScreen.currentContext, isNotNull);
    expect(
      a.tour.readingScreen.currentContext,
      isNot(same(b.tour.readingScreen.currentContext)),
    );
  });

  testWidgets('בלי scope — יעדי החלון הנוכחי', (tester) async {
    late TourTargetKeys resolved;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          resolved = TourTargetKeys.of(context);
          return const SizedBox();
        },
      ),
    );

    expect(resolved, same(AppWindowKeys.current.tour));
  });

  testWidgets('חלונית הניווט הפעילה מתפרסמת בחלון שלה בלבד', (tester) async {
    final window = _FakeWindow();
    final a = AppWindowKeys();
    final b = AppWindowKeys();

    Widget panel(AppWindowKeys keys, {required bool active}) => AppWindowScope(
      controller: window,
      geometry: window,
      keys: keys,
      child: TextBookNavPanelTourTarget(
        isActiveTab: active,
        child: const SizedBox(width: 10, height: 10),
      ),
    );

    await tester.pumpWidget(
      Column(children: [panel(a, active: true), panel(b, active: false)]),
    );

    expect(a.tour.activeTextBookNavPanel?.currentContext, isNotNull);
    expect(b.tour.activeTextBookNavPanel, isNull);
    expect(AppWindowKeys.current.tour.activeTextBookNavPanel, isNull);

    await tester.pumpWidget(const SizedBox());
    expect(a.tour.activeTextBookNavPanel, isNull);
  });
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}
