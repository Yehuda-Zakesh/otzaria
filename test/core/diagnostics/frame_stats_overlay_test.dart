import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/frame_stats_overlay.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late String outputPath;

  setUp(() {
    outputPath =
        '${Directory.systemTemp.createTempSync('diag').path}/out.jsonl';
    DeveloperDiagnostics.instance
      ..resetForTesting()
      ..outputPath = outputPath
      ..errorLogWriter = (_) {};
  });

  tearDown(() => DeveloperDiagnostics.instance.resetForTesting());

  Widget host() => const MaterialApp(home: FrameStatsOverlay(child: _Probe()));

  Future<void> pressShortcut(
    WidgetTester tester, {
    LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft,
  }) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('Ctrl+Shift+I turns developer mode on and off', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byType(FrameStatsPanel), findsNothing);

    await pressShortcut(tester);
    expect(find.byType(FrameStatsPanel), findsOneWidget);
    expect(DeveloperDiagnostics.instance.isCollecting, isTrue);

    await pressShortcut(tester);
    expect(find.byType(FrameStatsPanel), findsNothing);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });

  testWidgets('Cmd+Shift+I works too', (tester) async {
    await tester.pumpWidget(host());
    await pressShortcut(tester, modifier: LogicalKeyboardKey.metaLeft);
    expect(find.byType(FrameStatsPanel), findsOneWidget);

    await pressShortcut(tester, modifier: LogicalKeyboardKey.metaLeft);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });

  testWidgets('Ctrl+I and Shift+I are ignored', (tester) async {
    await tester.pumpWidget(host());
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump();
    expect(find.byType(FrameStatsPanel), findsNothing);
    expect(DeveloperDiagnostics.instance.isCollecting, isFalse);
  });

  testWidgets('toggling the panel keeps the app state', (tester) async {
    await tester.pumpWidget(host());
    final before = tester.state(find.byType(_Probe));

    await pressShortcut(tester);
    await tester.pump();
    expect(identical(tester.state(find.byType(_Probe)), before), isTrue);

    await pressShortcut(tester);
    expect(identical(tester.state(find.byType(_Probe)), before), isTrue);
  });

  testWidgets('the panel works above the Navigator, as in App.builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FrameStatsOverlay(child: child!),
        home: const _Probe(),
      ),
    );
    DeveloperDiagnostics.instance.toggle();
    await tester.pump();

    final stats = find.textContaining('frames/s');
    expect(stats, findsOneWidget);
    expect(
      find.ancestor(of: stats, matching: find.byType(Material)),
      findsWidgets,
      reason: 'text without a Material ancestor renders with debug underlines',
    );
    await tester.tap(find.byType(IconButton).first);
    await tester.pump();
    expect(tester.takeException(), isNull);

    DeveloperDiagnostics.instance.resetForTesting();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed snapshot reports an error instead of saved', (
    tester,
  ) async {
    final blocked = File('$outputPath.blocked')..writeAsStringSync('blocked');
    DeveloperDiagnostics.instance.outputPath = '${blocked.path}/out.jsonl';
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        builder: (context, child) => FrameStatsOverlay(child: child!),
        home: const _Probe(),
      ),
    );
    DeveloperDiagnostics.instance.toggle();
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(FluentIcons.camera_24_regular));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump();
    expect(find.text(CommonMessages.diagnosticsSaveError), findsOneWidget);
    expect(find.textContaining('saved:'), findsNothing);
    expect(tester.takeException(), isNull);
    UiSnack.hide();
    await tester.pump();
  });

  test('formatFrameStats shows timings, memory and top rebuilds', () {
    final text = formatFrameStats(
      const FrameStats(
        framesPerSecond: 2,
        buildAvgMs: 12,
        buildMaxMs: 30,
        rasterAvgMs: 2,
        rasterMaxMs: 4,
        slowInWindow: 1,
        slowTotal: 7,
        rssMb: 420,
        peakRssMb: 512,
        topRebuilds: [MapEntry('TextBookScreen', 10)],
      ),
    );
    expect(text, contains('frames/s  2'));
    expect(text, contains('build ms  avg 12.0  max 30.0'));
    expect(text, contains('raster ms avg 2.0  max 4.0'));
    expect(text, contains('slow      1 (2s)  total 7'));
    expect(text, contains('memory    420 MB  peak 512 MB'));
    expect(text, contains('rebuild   10x TextBookScreen'));
  });

  test('formatFrameStats handles an idle window', () {
    final text = formatFrameStats(const FrameStats());
    expect(text, contains('frames/s  0'));
    expect(text, contains('avg -  max -'));
  });
}
