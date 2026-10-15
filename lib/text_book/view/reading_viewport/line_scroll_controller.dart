/// גלילה ומיקום של הקורא בשורות מקור; מחוץ לתצוגה (bloc, טאבים, ניווט,
/// תוספים) אין אינדקסי פריטים — רק [LineScrollController].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:otzaria/text_book/utils/reading_position.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:otzaria/widgets/lists/scroll_position_reanchor.dart';

export 'package:otzaria/text_book/utils/reading_position.dart';

/// ניווט של קורא חיצוני (תוסף שמחליף את תצוגת הטקסט) — שורת מקור בלבד.
typedef ExternalLineNavigator = Future<void> Function(int line);

/// מה שהתצוגה המחוברת מספקת: הפריסה מול התוכן הנוכחי, וגובה התצוגה.
class ReadingViewportBinding {
  const ReadingViewportBinding({
    required this.segments,
    required this.viewportExtent,
  });

  final ReadingSegments? Function() segments;
  final double Function() viewportExtent;
}

class _Target {
  _Target({
    required this.line,
    this.alignment = kReadingAnchorAlignment,
    this.intraLineFraction = 0,
    this.duration = Duration.zero,
    this.curve = Curves.ease,
    this.waitForAttach = false,
  });

  _Target.anchor(ReadingAnchor anchor)
    : this(
        line: anchor.line,
        alignment: anchor.alignment,
        intraLineFraction: anchor.intraLineFraction,
      );

  final int line;
  final double alignment;
  final double intraLineFraction;
  final Duration duration;
  final Curve curve;
  bool waitForAttach;

  _Target get instant => _Target(
    line: line,
    alignment: alignment,
    intraLineFraction: intraLineFraction,
  );
}

class LineScrollController {
  LineScrollController() {
    positionsListener.itemPositions.addListener(_onItemPositions);
  }

  /// לשימוש הרשימה, פס הגלילה, [ScrollPositionReanchor] ו-ProgressiveScroll בלבד.
  @internal
  final JumpAwareItemScrollController itemController =
      JumpAwareItemScrollController();
  @internal
  final ItemPositionsListener positionsListener =
      ItemPositionsListener.create();
  @internal
  final ScrollOffsetController offsetController = ScrollOffsetController();

  /// פריטי הרשימה הבנויים — מיקום שורה בפסקה נמדד מהם ולא מוערך.
  @internal
  final ReaderItemBoxes itemBoxes = ReaderItemBoxes();

  final ValueNotifier<ReadingPosition?> _position = ValueNotifier(null);

  /// המיקום הנוכחי, או יעד הניווט מרגע שהתחיל ועד שנחת.
  ValueListenable<ReadingPosition?> get position => _position;

  ReadingViewportBinding? _binding;
  ExternalLineNavigator? _external;
  _Target? _pending;

  /// יעד שנחת על פריט שטרם נטען: ממתינים לטעינתו ומדייקים שוב.
  _Target? _awaitingLoad;
  int _token = 0;
  int _navigating = 0;
  ReadingSegments? _measuredSegments;

  /// העוגן מהמדידה האחרונה — נשמר כמספר שורה, כי הפריסה עשויה להשתנות אחריה.
  ReadingAnchor? _measuredAnchor;
  bool _userScrollActive = false;
  bool _disposed = false;

  bool get isAttached => _external != null || _nativeReady;

  bool get hasPendingTarget => _pending != null;

  ReadingSegments? get _segments => _binding?.segments();

  bool get _nativeReady =>
      _binding != null &&
      itemController.isAttached &&
      (_segments?.isNotEmpty ?? false);

  ExternalLineNavigator? get externalNavigator => _external;

  set externalNavigator(ExternalLineNavigator? navigator) {
    _external = navigator;
    if (navigator != null) _forgetMeasured();
    final pending = _pending;
    if (navigator != null && pending != null) {
      _pending = null;
      unawaited(navigator(pending.line));
    }
  }

  void addBeforeJumpListener(VoidCallback listener) =>
      itemController.addBeforeJumpListener(listener);

  void removeBeforeJumpListener(VoidCallback listener) =>
      itemController.removeBeforeJumpListener(listener);

  /// מחבר תצוגה. תצוגה שמתחלפת חוזרת לעוגן האחרון, אלא אם ממתין ניווט.
  void attach(ReadingViewportBinding binding) {
    _binding = binding;
    final pending = _pending;
    if (pending != null) {
      pending.waitForAttach = false;
    } else if (_measuredSegments != null) {
      final anchor = _measuredAnchor;
      if (anchor != null) _pending = _Target.anchor(anchor);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushPending());
  }

  void detach(ReadingViewportBinding binding) {
    if (identical(_binding, binding)) _binding = null;
  }

  /// גלילה לשורת המקור [line]. בלי תצוגה מחוברת היעד נשמר ומבוצע בחיבור.
  Future<void> scrollToLine(
    int line, {
    double alignment = kReadingAnchorAlignment,
    double intraLineFraction = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.ease,
  }) {
    final segments = _segments;
    final target = _Target(
      line: segments == null || segments.isEmpty
          ? (line < 0 ? 0 : line)
          : line.clamp(0, segments.layout.lineCount - 1).toInt(),
      alignment: alignment,
      intraLineFraction: intraLineFraction,
      duration: duration,
      curve: curve,
    );
    _awaitingLoad = null;
    _publish(
      ReadingPosition.target(
        target.line,
        intraLineFraction: intraLineFraction,
      ),
    );
    final external = _external;
    if (external != null) {
      _forgetMeasured();
      _pending = null;
      _token++;
      itemController.notifyBeforeJump();
      return external(target.line);
    }
    if (!_nativeReady) {
      _token++;
      _pending = target;
      return Future.value();
    }
    _pending = null;
    return _run(target);
  }

  Future<void> jumpToLine(
    int line, {
    double alignment = kReadingAnchorAlignment,
    double intraLineFraction = 0,
  }) => scrollToLine(
    line,
    alignment: alignment,
    intraLineFraction: intraLineFraction,
    duration: Duration.zero,
  );

  /// היעד יבוצע רק בתצוגה הבאה שתתחבר — למשל ביציאה מצורת הדף.
  void scrollToLineOnNextAttach(int line) {
    _awaitingLoad = null;
    _token++;
    _publish(ReadingPosition.target(line));
    _pending = _Target(line: line, waitForAttach: true);
  }

  /// מיקום שדווח מקורא חיצוני.
  void reportExternalLine(int line) {
    if (line < 0) return;
    _forgetMeasured();
    _publish(ReadingPosition.target(line));
  }

  /// המדידה האחרונה של הרשימה אינה המיקום עוד; בלי זה חיבור מחדש היה חוזר אליה.
  void _forgetMeasured() {
    _measuredSegments = null;
    _measuredAnchor = null;
  }

  /// לעטיפת רשימת הקורא: מבחין בין גלילת משתמש לבין ניווט ושינויי גובה.
  Widget trackUserScroll(Widget list) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: list,
      );

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      // גרירה של המשתמש מבטלת ניווט שבדרך, אחרת הדיוק היה מחזיר אליו.
      if (notification.dragDetails != null && _navigating > 0) _cancelRun();
      _userScrollActive = _navigating == 0 || notification.dragDetails != null;
    } else if (notification is ScrollEndNotification) {
      _userScrollActive = false;
    } else if (notification is ScrollUpdateNotification && _navigating == 0) {
      // רק גלילה של המשתמש מוותרת על דיוק ממתין; שינוי גובה אינו גולל.
      _awaitingLoad = null;
    }
    return false;
  }

  void _cancelRun() {
    _token++;
    _pending = null;
    _awaitingLoad = null;
  }

  /// הנקודה שעל קו העוגן עכשיו.
  ReadingAnchor? captureAnchor() {
    final segments = _segments;
    if (segments == null || _external != null) {
      final current = _position.value;
      return current == null
          ? null
          : ReadingAnchor(
              line: current.topLine,
              intraLineFraction: current.intraLineFraction,
            );
    }
    return readingAnchorFromItems(
      segments,
      positionsListener.itemPositions.value,
      measure: itemBoxes.lineExtent,
    );
  }

  /// לפני שינוי רוחב: קובע את הרשימה על הפריט העליון, ואחרי הפריסה מחזיר את
  /// השורה המדויקת לקו העוגן.
  void keepViewAcrossRelayout() {
    if (!_nativeReady) return;
    final anchor = captureAnchor();
    if (anchor == null) return;
    final top = reanchorTargetPosition(positionsListener.itemPositions.value);
    if (top != null) {
      itemController.jumpTo(index: top.index, alignment: top.itemLeadingEdge);
    }
    final token = ++_token;
    _navigating++;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      _navigating--;
      if (token != _token || _disposed) return;
      await _run(_Target.anchor(anchor));
    });
  }

  void _publish(ReadingPosition position) {
    if (_disposed || _position.value == position) return;
    _position.value = position;
  }

  void _flushPending() {
    final pending = _pending;
    if (_disposed || pending == null || pending.waitForAttach) return;
    if (!_nativeReady) return;
    _pending = null;
    unawaited(_run(pending));
  }

  Future<void> _run(_Target target) async {
    final binding = _binding;
    final segments = _segments;
    if (binding == null || segments == null || segments.isEmpty) return;
    final token = ++_token;
    _navigating++;
    try {
      await scrollToSourceLine(
        scrollController: itemController,
        scrollOffsetController: offsetController,
        positionsListener: positionsListener,
        segments: segments,
        latestSegments: () => _segments ?? segments,
        lineIndex: target.line,
        viewportExtent: binding.viewportExtent(),
        alignment: target.alignment,
        intraLineFraction: target.intraLineFraction,
        duration: target.duration,
        curve: target.curve,
        isCurrent: () => token == _token && !_disposed,
        measure: itemBoxes.lineExtent,
      );
    } finally {
      _navigating--;
    }
    if (token != _token || _disposed) {
      // ניווט שהמשתמש קטע: המיקום הוא מה שעל המסך עכשיו.
      if (_navigating == 0 && _pending == null && _external == null) {
        _measure();
      }
      return;
    }
    final landed = _segments;
    if (landed != null && landed.isNotEmpty) {
      final item = landed.layout.itemForLine(target.line);
      if (!landed[item].isLoaded) {
        _awaitingLoad = target.instant;
        return;
      }
    }
    _measure(landed: target);
  }

  ItemPosition? _positionOf(int item) => positionsListener.itemPositions.value
      .where((p) => p.index == item)
      .firstOrNull;

  void _onItemPositions() {
    if (_disposed || _external != null) return;
    final segments = _segments;
    if (segments == null || segments.isEmpty) return;
    final previousSegments = _measuredSegments;

    final pending = _pending;
    if (pending != null && !pending.waitForAttach) {
      _flushPending();
      return;
    }
    if (_navigating > 0) return;

    final awaiting = _awaitingLoad;
    if (awaiting != null) {
      _onPositionsWhileAwaitingLoad(awaiting, segments);
      return;
    }

    if (!_userScrollActive &&
        previousSegments != null &&
        !identical(previousSegments, segments)) {
      final anchor = _measuredAnchor;
      if (anchor != null &&
          _relayoutMovesAnchor(previousSegments, segments, anchor)) {
        // לא מודדים: המיקום שנמדד לפני השינוי הוא שנשמר.
        _measuredSegments = segments;
        unawaited(_run(_Target.anchor(anchor)));
        return;
      }
    }
    _measure();
  }

  /// פריסה חדשה (החלפת מצב רציף), או טעינה של שורה עד העוגן שהזיזה אותו.
  /// טעינה מתחת לעוגן אינה מזיזה אותו, ולכן גלילה שוטפת אינה נקטעת.
  bool _relayoutMovesAnchor(
    ReadingSegments before,
    ReadingSegments after,
    ReadingAnchor anchor,
  ) {
    if (!before.layout.hasSameStructure(after.layout)) return true;
    if (!_loadedChangedUpTo(before, after, anchor.line)) return false;
    final item = after.layout.itemForLine(anchor.line);
    final itemPosition = _positionOf(item);
    // העוגן מחוץ לתצוגה: המשתמש כבר במקום אחר (למשל קפיצה בפס הגלילה).
    if (itemPosition == null) return false;
    final extent = _binding?.viewportExtent() ?? 0;
    if (extent <= 0) return true;
    final edges = lineEdgesInViewport(
      after,
      anchor.line,
      itemPosition,
      measure: itemBoxes.lineExtent,
    );
    final edge =
        edges.leading +
        anchor.intraLineFraction * (edges.trailing - edges.leading);
    return ((edge - anchor.alignment) * extent).abs() > 0.5;
  }

  static bool _loadedChangedUpTo(
    ReadingSegments before,
    ReadingSegments after,
    int line,
  ) {
    final a = before.loadedLineFlags;
    final b = after.loadedLineFlags;
    if (identical(a, b)) return false;
    bool loaded(List<bool>? flags, int i) =>
        flags == null || (i < flags.length && flags[i]);
    for (var i = 0; i <= line; i++) {
      if (loaded(a, i) != loaded(b, i)) return true;
    }
    return false;
  }

  void _onPositionsWhileAwaitingLoad(
    _Target awaiting,
    ReadingSegments segments,
  ) {
    final item = segments.layout.itemForLine(awaiting.line);
    if (segments[item].isLoaded) {
      _awaitingLoad = null;
      _measuredSegments = segments;
      unawaited(_run(awaiting));
      return;
    }
    _measuredSegments = segments;
  }

  /// [landed] — יעד שהניווט נחת בו הוא המיקום, גם כשנעצר מעל קו העוגן (ראש
  /// הספר, שורה קצרה שיושרה ל-0) או חולק שורת תצוגה עם שורות קודמות.
  void _measure({_Target? landed}) {
    final segments = _segments;
    if (segments == null || segments.isEmpty) return;
    final positions = positionsListener.itemPositions.value.toList();
    _measuredSegments = segments;
    var position = readingPositionFromItems(
      segments,
      positions,
      measure: itemBoxes.lineExtent,
    );
    if (position == null) {
      _measuredAnchor = null;
      return;
    }
    if (landed != null &&
        position.topLine != landed.line &&
        (_restsAt(segments, landed) ||
            position.topLine < landed.line &&
                _restsAtOrAbove(segments, landed))) {
      position = ReadingPosition(
        topLine: landed.line,
        intraLineFraction: landed.intraLineFraction,
        visibleLines: List<int>.unmodifiable({
          landed.line,
          ...position.visibleLines.where((line) => line > landed.line),
        }),
        windowFirstLine: position.windowFirstLine,
        windowLastLine: position.windowLastLine,
      );
    }
    _measuredAnchor = readingAnchorAt(
      segments,
      positions,
      position,
      measure: itemBoxes.lineExtent,
    );
    _publish(position);
  }

  bool _restsAtOrAbove(ReadingSegments segments, _Target target) {
    final top = _positionOf(0);
    if (top == null || top.itemLeadingEdge < 0) return false;
    final item = segments.layout.itemForLine(target.line);
    final itemPosition = _positionOf(item);
    if (itemPosition == null) return false;
    final edges = lineEdgesInViewport(
      segments,
      target.line,
      itemPosition,
      measure: itemBoxes.lineExtent,
    );
    return edges.leading >= 0 &&
        edges.leading <= target.alignment + kAnchorLandingEpsilon;
  }

  bool _restsAt(ReadingSegments segments, _Target target) {
    final item = segments.layout.itemForLine(target.line);
    final itemPosition = _positionOf(item);
    if (itemPosition == null) return false;
    final edges = lineEdgesInViewport(
      segments,
      target.line,
      itemPosition,
      measure: itemBoxes.lineExtent,
    );
    return (edges.leading - target.alignment).abs() <= kAnchorLandingEpsilon;
  }

  void dispose() {
    _disposed = true;
    positionsListener.itemPositions.removeListener(_onItemPositions);
  }
}

/// מספק את [LineScrollController] של הקורא למי שאין לו גישה לטאב.
class LineScrollScope extends InheritedWidget {
  const LineScrollScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final LineScrollController controller;

  static LineScrollController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LineScrollScope>()?.controller;

  @override
  bool updateShouldNotify(LineScrollScope oldWidget) =>
      !identical(oldWidget.controller, controller);
}
