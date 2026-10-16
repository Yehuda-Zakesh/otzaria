import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// עוטף פריט של רשימת גלילה ממורכזת (`ScrollablePositionedList`) כדי שאזור
/// הבחירה ימיין אותו לפי מיקומו האמיתי ב-viewport.
///
/// הפריטים שלפני נקודת העיגון של הרשימה יושבים ב-sliver הפוך. כשה-sliver
/// הזה נגלל כולו אל מעל החלון, Flutter מחשב לפריטיו (שעדיין חיים בתחום
/// המטמון) טרנספורם שגוי — הם "נוחתים" בראש ה-viewport — ולכן נדחפים
/// לאמצע סדר הבחירה, וגרירת בחירה כלפי מעלה נעצרת בהם במקום להמשיך
/// לפסקה שמעל. כאן הטרנספורם מתוקן לפי היסט הגלילה האמיתי של הפריט.
class ViewportAlignedSelectionContainer extends StatefulWidget {
  const ViewportAlignedSelectionContainer({super.key, required this.child});

  final Widget child;

  @override
  State<ViewportAlignedSelectionContainer> createState() =>
      _ViewportAlignedSelectionContainerState();
}

class _ViewportAlignedSelectionContainerState
    extends State<ViewportAlignedSelectionContainer> {
  // התוכן ולא התיבה: הטקסט ממיר קואורדינטות בלי תיקון הטרנספורם שלה.
  late final _delegate = _ItemSelectionDelegate(
    () => (context.findRenderObject() as RenderViewportAlignedBox?)?.child,
  );

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SelectionContainer מדווח את מיקומו דרך אובייקט הרינדור הראשון שמתחתיו,
    // ולכן התיקון חייב לשבת שם ולא ב-delegate.
    return SelectionContainer(
      delegate: _delegate,
      child: _ViewportAlignedBox(child: widget.child),
    );
  }
}

/// Flutter שומר את קצות הבחירה בקואורדינטות מסך ומשדר אותם שוב כשהטקסט נבנה
/// מחדש; אחרי גלילה הם נוחתים על טקסט אחר, ולכן נשמרים יחסית לפריט.
class _ItemSelectionDelegate extends StaticSelectionContainerDelegate {
  _ItemSelectionDelegate(this._box);

  final RenderObject? Function() _box;
  final _edges = <bool, Offset>{};

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final p = event.globalPosition;
    final text = [
      for (final s in selectables)
        MatrixUtils.transformRect(
          s.getTransformTo(null),
          s.boundingBoxes.reduce((a, b) => a.expandToInclude(b)),
        ),
    ].fold<Rect?>(null, (all, r) => all?.expandToInclude(r) ?? r);
    if (text == null ||
        p.dy < text.top ||
        p.dy >= text.bottom ||
        text.contains(p)) {
      return super.handleSelectionEdgeUpdate(event);
    }
    final edgeEvent = event.type == SelectionEventType.startEdgeUpdate
        ? SelectionEdgeUpdateEvent.forStart
        : SelectionEdgeUpdateEvent.forEnd;
    return super.handleSelectionEdgeUpdate(
      edgeEvent(
        globalPosition: Offset(
          p.dx < text.left ? text.left : text.right - 1,
          p.dy,
        ),
        granularity: event.granularity,
      ),
    );
  }

  @override
  void updateLastSelectionEdgeLocation({
    required Offset globalSelectionEdgeLocation,
    required bool forEnd,
  }) {
    if (_box() case final RenderBox box when box.attached) {
      _edges[forEnd] = box.globalToLocal(globalSelectionEdgeLocation);
    }
    super.updateLastSelectionEdgeLocation(
      globalSelectionEdgeLocation: globalSelectionEdgeLocation,
      forEnd: forEnd,
    );
  }

  @override
  void clearInternalSelectionState() {
    _edges.clear();
    super.clearInternalSelectionState();
  }

  @override
  void didChangeSelectables() {
    if (_box() case final RenderBox box when box.attached) {
      _edges.forEach(
        (forEnd, edge) => super.updateLastSelectionEdgeLocation(
          globalSelectionEdgeLocation: box.localToGlobal(edge),
          forEnd: forEnd,
        ),
      );
    }
    super.didChangeSelectables();
  }
}

class _ViewportAlignedBox extends SingleChildRenderObjectWidget {
  const _ViewportAlignedBox({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderViewportAlignedBox();
}

/// תיבה שקופה שמדווחת טרנספורם לפי מיקומה האמיתי בתוך ה-viewport העוטף,
/// גם כשה-sliver שלה נגלל כולו מחוץ לתצוגה. חשופה לצורכי בדיקות.
class RenderViewportAlignedBox extends RenderProxyBox {
  bool _resolving = false;

  @override
  Matrix4 getTransformTo(RenderObject? target) {
    final transform = super.getTransformTo(target);
    // getOffsetToReveal קורא בעצמו ל-getTransformTo של היעד — בלי השומר
    // זו רקורסיה אינסופית.
    if (_resolving || !hasSize) return transform;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderViewportBase || !_isAncestorOf(target, viewport)) {
      return transform;
    }
    _resolving = true;
    try {
      // getOffsetToReveal מחזיר היסט גלילה גולמי; ב-viewport מעוגן (anchor)
      // הציור מוסט ב-anchor * הציר הראשי, וללא ההוספה כל הפריטים נדחפים למעלה.
      final anchorShift = viewport is RenderViewport
          ? viewport.anchor *
                (viewport.axis == Axis.vertical
                    ? viewport.size.height
                    : viewport.size.width)
          : 0.0;
      final trueTop =
          viewport.getOffsetToReveal(this, 0).offset -
          viewport.offset.pixels +
          anchorShift;
      final toViewport = super.getTransformTo(viewport);
      final reportedTop = MatrixUtils.transformPoint(
        toViewport,
        Offset.zero,
      ).dy;
      final dy = trueTop - reportedTop;
      if (dy.abs() < 0.5) return transform;
      return viewport.getTransformTo(target) *
          Matrix4.translationValues(0, dy, 0) *
          toViewport;
    } finally {
      _resolving = false;
    }
  }

  static bool _isAncestorOf(RenderObject? ancestor, RenderObject node) {
    if (ancestor == null) return true;
    for (
      RenderObject? current = node;
      current != null;
      current = current.parent
    ) {
      if (identical(current, ancestor)) return true;
    }
    return false;
  }
}
