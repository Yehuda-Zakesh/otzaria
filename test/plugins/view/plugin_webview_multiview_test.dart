import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';

/// ריבוי חלונות: WebView של תוסף נוצר תחת התצוגה שמציגה אותו, ועובר איתה.
/// נבדק דרך המימוש של Windows שבפורק, עם ערוצים מדומים.
const int _textureId = 3;
const MethodChannel _managerChannel = MethodChannel(
  'com.pichillilorenzo/flutter_inappwebview_manager',
);
const MethodChannel _viewChannel = MethodChannel(
  'com.pichillilorenzo/custom_platform_view_$_textureId',
);
const EventChannel _viewEvents = EventChannel(
  'com.pichillilorenzo/custom_platform_view_${_textureId}_events',
);

class _SecondaryTestView extends TestFlutterView {
  _SecondaryTestView(TestFlutterView base)
    : super(
        view: base,
        platformDispatcher: base.platformDispatcher,
        display: base.display,
      );

  @override
  int get viewId => 7;

  @override
  void render(ui.Scene scene, {Size? size}) {}
}

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> managerCalls;
  late List<MethodCall> viewCalls;
  InAppWebViewPlatform? previousPlatform;

  setUp(() {
    previousPlatform = InAppWebViewPlatform.instance;
    WindowsInAppWebViewPlatform.registerWith();
    managerCalls = [];
    viewCalls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_managerChannel, (call) async {
      managerCalls.add(call);
      return call.method == 'createInAppWebView' ? _textureId : null;
    });
    messenger.setMockMethodCallHandler(_viewChannel, (call) async {
      viewCalls.add(call);
      return null;
    });
    messenger.setMockStreamHandler(
      _viewEvents,
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_managerChannel, null);
    messenger.setMockMethodCallHandler(_viewChannel, null);
    messenger.setMockStreamHandler(_viewEvents, null);
    if (previousPlatform case final platform?) {
      InAppWebViewPlatform.instance = platform;
    }
  });

  Map<dynamic, dynamic> createArguments() =>
      managerCalls
              .singleWhere((call) => call.method == 'createInAppWebView')
              .arguments
          as Map<dynamic, dynamic>;

  Widget webView({Key? key}) => Directionality(
    textDirection: TextDirection.rtl,
    child: InAppWebView(
      key: key,
      initialData: InAppWebViewInitialData(data: '<p></p>'),
    ),
  );

  testWidgets('בחלון הראשי היצירה אינה נושאת מזהה תצוגה', (tester) async {
    await tester.pumpWidget(webView());
    await tester.pump();

    expect(createArguments().containsKey('flutterViewId'), isFalse);
    expect(
      viewCalls.where((call) => call.method == 'setFlutterViewId'),
      isEmpty,
    );
  }, variant: _windows);

  testWidgets('בחלון Dart היצירה נושאת את מזהה התצוגה שלו', (tester) async {
    final secondary = _SecondaryTestView(tester.view);
    await tester.pumpWidget(
      ViewCollection(
        views: [
          View(view: tester.view, child: const SizedBox()),
          View(view: secondary, child: webView()),
        ],
      ),
      wrapWithView: false,
    );
    await tester.pump();

    expect(createArguments()['flutterViewId'], 7);
  }, variant: _windows);

  testWidgets('מעבר לחלון אחר מצמיד מחדש בלי ליצור WebView חדש', (
    tester,
  ) async {
    final secondary = _SecondaryTestView(tester.view);
    // כמו ה-GlobalKey של PluginTabPage: ה-WebView שורד החלפת הורה.
    final key = GlobalKey();
    Widget host({required bool inSecondary}) => ViewCollection(
      views: [
        View(
          view: tester.view,
          child: inSecondary ? const SizedBox() : webView(key: key),
        ),
        View(
          view: secondary,
          child: inSecondary ? webView(key: key) : const SizedBox(),
        ),
      ],
    );

    await tester.pumpWidget(host(inSecondary: false), wrapWithView: false);
    await tester.pump();
    expect(createArguments().containsKey('flutterViewId'), isFalse);

    await tester.pumpWidget(host(inSecondary: true), wrapWithView: false);
    await tester.pump();

    expect(
      viewCalls
          .where((call) => call.method == 'setFlutterViewId')
          .single
          .arguments,
      7,
    );
    expect(
      managerCalls.where((call) => call.method == 'createInAppWebView'),
      hasLength(1),
    );
  }, variant: _windows);
}
