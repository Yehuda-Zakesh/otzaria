import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> windowManagerCalls;
  late List<MethodCall> platformCalls;

  setUp(() {
    windowManagerCalls = [];
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (
          call,
        ) async {
          windowManagerCalls.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  late List<bool> persisted;

  WindowFullscreenCubit buildCubit() {
    persisted = [];
    final cubit = WindowFullscreenCubit(
      initial: false,
      persist: (value) async => persisted.add(value),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> toggleAsDesktop(BuildContext context, bool isFullscreen) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await FullscreenHelper.toggleFullscreen(context, isFullscreen);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets(
    'toggleFullscreen שנקרא מהקשר אחד משתקף מיד ב-WindowFullscreenCubit '
    'של החלון שנקרא ממסך אחר',
    (tester) async {
      final fullscreenCubit = buildCubit();
      late BuildContext readingScreenContext;
      late BuildContext settingsScreenContext;

      await pumpWithAppWindow(
        tester,
        BlocProvider<WindowFullscreenCubit>.value(
          value: fullscreenCubit,
          child: MaterialApp(
            home: Column(
              children: [
                Builder(
                  builder: (context) {
                    readingScreenContext = context;
                    return const SizedBox();
                  },
                ),
                Builder(
                  builder: (context) {
                    settingsScreenContext = context;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        settingsScreenContext.read<WindowFullscreenCubit>().state,
        isFalse,
      );

      await toggleAsDesktop(readingScreenContext, true);
      await tester.pump();

      expect(
        settingsScreenContext.read<WindowFullscreenCubit>().state,
        isTrue,
        reason:
            'שני המסכים חולקים את מצב החלון; שינוי מכל אחד מהם '
            'צריך להשתקף מיד באחר',
      );
    },
  );

  testWidgets(
    'toggleFullscreen(true) מסתיר את הכותרת לפני setFullScreen, ו-(false) '
    'משאיר אותה מוסתרת (CustomTitleBar) — עקבי בכל קריאה',
    (tester) async {
      final fullscreenCubit = buildCubit();
      late BuildContext context;

      await pumpWithAppWindow(
        tester,
        BlocProvider<WindowFullscreenCubit>.value(
          value: fullscreenCubit,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await toggleAsDesktop(context, true);

      final methodsWhenEntering = windowManagerCalls
          .map((c) => c.method)
          .toList();
      expect(
        methodsWhenEntering.indexOf('setTitleBarStyle'),
        lessThan(methodsWhenEntering.indexOf('setFullScreen')),
        reason: 'הסתרת ה-titlebar חייבת לקרות לפני setFullScreen (מונע הבהוב)',
      );

      windowManagerCalls.clear();
      await toggleAsDesktop(context, false);

      expect(
        windowManagerCalls.map((c) => c.method),
        containsAll(['setFullScreen', 'setTitleBarStyle']),
        reason: 'גם ביציאה ממסך מלא ה-titlebar המותאם-אישית נשאר מוסתר',
      );
    },
  );

  testWidgets(
    'קריאה חוזרת עם אותו מצב אינה פולטת ואינה שומרת שוב',
    (tester) async {
      final fullscreenCubit = buildCubit();
      late BuildContext context;

      await pumpWithAppWindow(
        tester,
        BlocProvider<WindowFullscreenCubit>.value(
          value: fullscreenCubit,
          child: MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final emitted = <bool>[];
      final subscription = fullscreenCubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await toggleAsDesktop(context, true);
      await tester.pump();
      await toggleAsDesktop(context, true);
      await tester.pump();

      expect(
        emitted,
        [true],
        reason: 'אין emit כפול כשהמצב לא באמת השתנה',
      );
      expect(persisted, [true]);
    },
  );

  testWidgets('במובייל toggleFullscreen מפעיל את SystemChrome', (tester) async {
    final fullscreenCubit = buildCubit();
    late BuildContext context;

    await pumpWithAppWindow(
      tester,
      BlocProvider<WindowFullscreenCubit>.value(
        value: fullscreenCubit,
        child: MaterialApp(
          home: Builder(
            builder: (currentContext) {
              context = currentContext;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await FullscreenHelper.toggleFullscreen(context, true);

      final call = platformCalls.singleWhere(
        (item) => item.method == 'SystemChrome.setEnabledSystemUIMode',
      );
      expect(call.arguments, 'SystemUiMode.immersiveSticky');
      expect(windowManagerCalls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// `FullscreenHelper.toggleFullscreen` שולף את החלון מ-[AppWindowScope],
/// ולכן כל עץ שנבדק חייב אותו מעליו. הבקר האמיתי מנתב לאותו
/// MethodChannel שכבר ממוקם כאן, ולכן ההנחות על `windowManagerCalls`
/// נשארות בתוקף.
Future<void> pumpWithAppWindow(WidgetTester tester, Widget child) =>
    tester.pumpWidget(
      AppWindowScope(
        controller: const WindowManagerAppWindowController(),
        geometry: const WindowManagerAppWindowController(),
        child: child,
      ),
    );
