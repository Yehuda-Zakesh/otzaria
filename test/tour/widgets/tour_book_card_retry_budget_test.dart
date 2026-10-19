import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';

import '../../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('כרטיס ספר שלא נפתר מפסיק לרנדר מחדש אחרי תקרת הפריימים', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = TourCubit()..start(libraryLoaded: true);
    cubit.goToStep(
      cubit.state.steps.indexWhere((step) => step.id == 'open_book'),
    );

    var resolveCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        // גופן הבדיקות רחב-קבוע ושורת הכפתורים נשפכת בו; ההקטנה מרחיקה את
        // חריגת הפריסה מהבדיקה, שעניינה מספר הרינדורים בלבד.
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
          child: BlocProvider.value(
            value: cubit,
            child: Stack(
              children: [
                TourOverlayScreen(
                  onStepChanged: (_) {},
                  // כרטיס הספר לעולם אינו נפתר — התרחיש שגרם ללולאה האינסופית.
                  targetRectResolver: (_) {
                    resolveCalls++;
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 300; i++) {
      await tester.pump();
    }
    final callsAfterBudget = resolveCalls;

    for (var i = 0; i < 100; i++) {
      await tester.pump();
    }

    expect(
      resolveCalls,
      callsAfterBudget,
      reason: 'הרינדור-מחדש חייב להיעצר בתקרה ולא להימשך בכל פריים',
    );
    expect(callsAfterBudget, lessThan(300));

    await cubit.close();
  });
}
