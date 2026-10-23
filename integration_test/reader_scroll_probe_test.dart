// מדידת גלילה בקורא הטקסט באפליקציה האמיתית: פותח ספרים לפי כותרת מדויקת
// מהספרייה, ומריץ בכל אחד גלילה רציפה דטרמיניסטית, fling וקפיצות רחוקות.
// לכל שלב נרשמים זמני פריימים (FrameTiming) ומוני SmartTextRenderStats.
//
// הרצה (profile, עם גיבוי ושחזור נתוני המשתמש):
//   tool/perf_probe/run_reader_scroll_probe.ps1
// הפלט: %TEMP%\otzaria_perf_probe\phases.jsonl ו-reader_scroll_summary.txt.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/app.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/main.dart' as app;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:path/path.dart' as p;

const _titles = [
  'בראשית',
  'משנה תורה, הלכות שבת',
  'שולחן ערוך, אורח חיים',
  'ברכות',
  'מיקרופדיה תלמודית',
];

/// ספרים שנמדדים שוב עם חלונית מפרשים פתוחה. סמני-האות של המפרשים מוזרקים
/// רק למפרשים פעילים; בשו"ע או"ח הם מופיעים ברוב השורות.
const _commentaryRuns = {
  'בראשית': ['רש"י על בראשית', 'רמב"ן על בראשית', 'אבן עזרא על בראשית'],
  'שולחן ערוך, אורח חיים': [
    'משנה ברורה',
    'מגן אברהם',
    'באר היטב אורח חיים',
  ],
};

/// גלילה רציפה: מספר פריימים × פיקסלים לפריים, קפיצה אחת בכל פריים.
const _stepFrames = 180;
const _stepPixels = 30.0;
const _animateDistance = 6000.0;
const _animateDuration = Duration(seconds: 4);
const _flingVelocity = 4000.0;
const _farJumpFractions = [0.25, 0.75, 0.1, 0.5, 0.9];

final _probeDir = Directory(
  p.join(Directory.systemTemp.path, 'otzaria_perf_probe'),
);
final _phasesFile = File(p.join(_probeDir.path, 'phases.jsonl'));
final _summaryFile = File(
  p.join(_probeDir.path, 'reader_scroll_summary.txt'),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('reader scroll probe', timeout: Timeout.none, (tester) async {
    _probeDir.createSync(recursive: true);
    for (final f in [_phasesFile, _summaryFile]) {
      if (f.existsSync()) f.deleteSync();
    }
    final rec = _Recorder(_phasesFile, binding);

    app.main(const <String>[]);
    await _waitUntil(
      tester,
      () => find.byType(App).evaluate().isNotEmpty,
      timeout: const Duration(minutes: 3),
    );
    final ctx = tester.element(find.byType(App));
    final tabsBloc = ctx.read<TabsBloc>();
    final library = await DataRepository.instance.library;
    tabsBloc.add(CloseAllTabs());
    // חימומי המטמון הנדחים של העלייה לא ייכנסו לשלב הראשון.
    await _pumpFor(tester, const Duration(seconds: 15));

    final settings = ctx.read<SettingsBloc>().state;
    final view = tester.view;
    rec.write({
      'type': 'meta',
      'pid': pid,
      'cores': Platform.numberOfProcessors,
      'startedAt': DateTime.now().toIso8601String(),
      'viewSize': [
        view.physicalSize.width / view.devicePixelRatio,
        view.physicalSize.height / view.devicePixelRatio,
      ],
      'devicePixelRatio': view.devicePixelRatio,
      'fontSize': settings.fontSize,
      'fontFamily': settings.fontFamily,
      'showTeamim': settings.showTeamim,
      'enableHtmlLinks': settings.enableHtmlLinks,
    });

    SmartTextRenderStats.enabled = true;
    final textBooks = library.getAllBooks().whereType<TextBook>().toList();
    for (final title in _titles) {
      final book = textBooks.where((b) => b.title == title).firstOrNull;
      if (book == null) {
        rec.write({'type': 'note', 'name': 'book_missing', 'title': title});
        continue;
      }
      await _probeBook(tester, rec, tabsBloc, book);
      final commentators = _commentaryRuns[title];
      if (commentators != null) {
        await _probeBook(
          tester,
          rec,
          tabsBloc,
          book,
          commentators: commentators,
        );
      }
    }
    SmartTextRenderStats.enabled = false;

    final summary = rec.summary();
    _summaryFile.writeAsStringSync(summary);
    // ignore: avoid_print
    print(summary);
  });
}

Future<void> _probeBook(
  WidgetTester tester,
  _Recorder rec,
  TabsBloc tabsBloc,
  TextBook book, {
  List<String>? commentators,
}) async {
  final withCommentary = commentators != null;
  final label = withCommentary ? '${book.title} +מפרשים' : book.title;
  tabsBloc.add(CloseAllTabs());
  await _pumpFor(tester, const Duration(seconds: 2));

  final tab = TextBookTab(
    book: book,
    index: 0,
    commentators: const [],
    splitedView: withCommentary,
    showPageShapeView: false,
  );
  await rec.phase(label, 'open', () async {
    tabsBloc.add(AddTab(tab));
    await _waitUntil(
      tester,
      () => tab.bloc.state is TextBookLoaded && tab.lines.isAttached,
      timeout: const Duration(seconds: 90),
    );
    TextBookLoaded loaded() => tab.bloc.state as TextBookLoaded;
    final wanted = commentators ?? const <String>[];
    // רשימת המפרשים הזמינים נטענת אחרי TextBookLoaded.
    await _waitUntil(
      tester,
      () => wanted.every(loaded().availableCommentators.contains),
      timeout: const Duration(seconds: 30),
      failSilently: true,
    );
    final active = [
      for (final title in wanted)
        if (loaded().availableCommentators.contains(title)) title,
    ];
    tab.bloc.add(UpdateCommentators(active));
    await _waitUntil(
      tester,
      () =>
          listEquals(loaded().activeCommentators, active) &&
          !loaded().linksLoading,
      timeout: const Duration(seconds: 30),
      failSilently: true,
    );
    await _pumpFor(tester, Duration(seconds: withCommentary ? 6 : 3));
  });

  final state = tab.bloc.state;
  if (state is! TextBookLoaded) {
    rec.write({'type': 'note', 'name': 'not_loaded', 'book': label});
    return;
  }
  final lineCount = state.content.length;
  rec.write({
    'type': 'note',
    'name': 'book',
    'book': label,
    'lineCount': lineCount,
    'linkLines': state.linksByLine.length,
    'anchorLines': state.linksByLine.values
        .where((links) => links.any((link) => link.anchorStart != null))
        .length,
    'showAnchorMarkers': state.bodyDisplayProfile.showAnchorMarkers,
    'activeCommentators': state.activeCommentators,
    'splitView': state.showSplitView,
  });

  ScrollPosition? position() {
    final controller = tab.lines.itemController.scrollController;
    return controller != null && controller.hasClients
        ? controller.position
        : null;
  }

  await rec.phase(label, 'scroll_steps', () async {
    for (var i = 0; i < _stepFrames; i++) {
      final pos = position();
      if (pos == null) break;
      pos.jumpTo(pos.pixels + _stepPixels);
      await SchedulerBinding.instance.endOfFrame;
    }
    await _pumpFor(tester, const Duration(milliseconds: 500));
  });

  await rec.phase(label, 'scroll_animate', () async {
    final pos = position();
    if (pos == null) return;
    unawaited(
      pos.animateTo(
        pos.pixels + _animateDistance,
        duration: _animateDuration,
        curve: Curves.linear,
      ),
    );
    await _pumpFor(
      tester,
      _animateDuration + const Duration(milliseconds: 500),
    );
  });

  await rec.phase(label, 'fling', () async {
    for (var i = 0; i < 2; i++) {
      final pos = position();
      if (pos is! ScrollPositionWithSingleContext) {
        rec.write({'type': 'note', 'name': 'fling_skipped', 'book': label});
        return;
      }
      pos.goBallistic(_flingVelocity);
      await _pumpFor(tester, const Duration(milliseconds: 2500));
    }
  });

  await rec.phase(label, 'far_jumps', () async {
    for (final fraction in _farJumpFractions) {
      final line = (lineCount * fraction).floor();
      final mark = rec.mark();
      unawaited(tab.lines.jumpToLine(line));
      await _pumpFor(tester, const Duration(milliseconds: 1500));
      rec.write({
        'type': 'jump',
        'book': label,
        'line': line,
        'frames': rec.framesSince(mark),
      });
    }
  });
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  bool failSilently = false,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!failSilently) fail('Timed out after $timeout');
}

class _Recorder {
  _Recorder(this.outFile, WidgetsBinding binding) {
    binding.addTimingsCallback(_onTimings);
  }

  final File outFile;
  final List<FrameTiming> _timings = [];
  final List<Map<String, Object?>> _phases = [];
  bool _active = false;

  void _onTimings(List<FrameTiming> timings) {
    if (_active) _timings.addAll(timings);
  }

  Future<void> phase(
    String book,
    String name,
    Future<void> Function() body,
  ) async {
    _timings.clear();
    SmartTextRenderStats.reset();
    _active = true;
    final watch = Stopwatch()..start();
    Object? error;
    try {
      await body();
    } catch (e) {
      error = e;
    }
    // timings של הפריימים האחרונים מדווחים באיחור.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _active = false;
    final record = <String, Object?>{
      'type': 'phase',
      'book': book,
      'name': '$book/$name',
      'phase': name,
      'durationMs': watch.elapsedMilliseconds,
      'frames': _frameStats(_timings),
      'smartText': SmartTextRenderStats.takeAndReset(),
      if (error != null) 'error': '$error',
    };
    _phases.add(record);
    write(record);
  }

  int mark() => _timings.length;

  /// מספר הפריימים ו-build המקסימלי מאז [mark].
  Map<String, Object?> framesSince(int mark) {
    final slice = _timings.length > mark ? _timings.sublist(mark) : const [];
    var maxBuild = 0.0;
    for (final t in slice) {
      final ms = t.buildDuration.inMicroseconds / 1000;
      if (ms > maxBuild) maxBuild = ms;
    }
    return {'count': slice.length, 'buildMaxMs': _round2(maxBuild)};
  }

  void write(Map<String, Object?> record) {
    outFile.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  String summary() {
    final out = StringBuffer(
      'book | phase | frames | build avg/p50/p90/p99/max | raster p90/max | '
      '>16 | >33 | work>16 | work>33 | fast/full | fwfh ms\n',
    );
    for (final r in _phases) {
      final f = r['frames']! as Map<String, Object?>;
      final s = r['smartText'] as Map<String, Object?>?;
      final fast = s == null
          ? 0
          : (s['fastInline']! as int) + (s['fastHeading']! as int);
      out.writeln(
        '${r['book']} | ${r['phase']} | ${f['count']} | '
        '${f['buildAvgMs']}/${f['buildP50Ms']}/${f['buildP90Ms']}/'
        '${f['buildP99Ms']}/${f['buildMaxMs']} | '
        '${f['rasterP90Ms']}/${f['rasterMaxMs']} | '
        '${f['over16Ms']} | ${f['over33Ms']} | '
        '${f['workOver16Ms']} | ${f['workOver33Ms']} | '
        '$fast/${s?['fullHtml'] ?? 0} | ${s?['fwfhBuildMs'] ?? 0}',
      );
    }
    return out.toString();
  }

  static Map<String, Object?> _frameStats(List<FrameTiming> timings) {
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final t in timings) ms(t.buildDuration)]..sort();
    final raster = [for (final t in timings) ms(t.rasterDuration)]..sort();
    final total = [for (final t in timings) ms(t.totalSpan)];
    // עבודת הפריים בלבד: totalSpan כולל גם המתנה ל-vsync ולתור, שתלויה בעומס
    // על המחשב ולא בקוד.
    final work = [
      for (final t in timings) ms(t.buildDuration) + ms(t.rasterDuration),
    ];
    final vsync = [for (final t in timings) ms(t.vsyncOverhead)]..sort();
    double pct(List<double> sorted, double q) =>
        sorted.isEmpty ? 0 : _round2(sorted[((sorted.length - 1) * q).round()]);
    return {
      'count': timings.length,
      'buildAvgMs': build.isEmpty
          ? 0
          : _round2(build.reduce((a, b) => a + b) / build.length),
      'buildP50Ms': pct(build, 0.5),
      'buildP90Ms': pct(build, 0.9),
      'buildP99Ms': pct(build, 0.99),
      'buildMaxMs': build.isEmpty ? 0 : _round2(build.last),
      'buildSumMs': _round2(build.fold(0.0, (a, b) => a + b)),
      'slowestBuildMs': [
        for (final v in build.reversed.take(5)) _round2(v),
      ],
      'rasterP90Ms': pct(raster, 0.9),
      'rasterMaxMs': raster.isEmpty ? 0 : _round2(raster.last),
      'over16Ms': total.where((v) => v > 1000 / 60).length,
      'over33Ms': total.where((v) => v > 33).length,
      'workOver16Ms': work.where((v) => v > 1000 / 60).length,
      'workOver33Ms': work.where((v) => v > 33).length,
      'vsyncOverheadP90Ms': pct(vsync, 0.9),
    };
  }

  static double _round2(double v) => (v * 100).round() / 100;
}
