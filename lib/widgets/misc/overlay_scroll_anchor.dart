import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// עוגן-גלילה לחלונית צפה: לוכד בנקודת מסך את ה-RenderBox העמוק ביותר
/// שמתחתיה, ומאפשר לחלונית לעקוב אחר תזוזת הנקודה בזמן גלילת התוכן.
class OverlayScrollAnchor {
  final RenderBox _box;
  final Offset _local;
  final List<Listenable> _scrollListenables;

  OverlayScrollAnchor._(this._box, this._local, this._scrollListenables);

  /// לוכד עוגן בנקודה גלובלית. יש לקרוא לפני שנפתח overlay מעל הנקודה,
  /// אחרת ה-hit-test יפגע בו במקום בתוכן. מחזיר null כשאין שם תוכן נגלל.
  static OverlayScrollAnchor? capture(
    BuildContext context,
    Offset globalPosition,
  ) {
    final view = View.maybeOf(context);
    if (view == null) return null;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, globalPosition, view.viewId);

    RenderBox? box;
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderBox && target.attached && target.hasSize) {
        box = target;
        break;
      }
    }
    if (box == null) return null;

    // איסוף ה-offsets של כל ה-viewports שמעל העוגן — שינוי בהם = גלילה.
    final listenables = <Listenable>[];
    RenderObject? node = box;
    while (node != null) {
      if (node is RenderViewportBase) {
        listenables.add(node.offset);
      }
      node = node.parent;
    }
    if (listenables.isEmpty) return null;

    return OverlayScrollAnchor._(
      box,
      box.globalToLocal(globalPosition),
      listenables,
    );
  }

  /// המיקום הגלובלי הנוכחי של נקודת העוגן, או null כשה-widget שעליו ישב
  /// העוגן כבר אינו מוצג: שורה שמוחזרה מחוץ ל-cache של רשימה נגללת, או טאב
  /// ברקע (keep-alive מקבל טרנספורם אפס, והמיקום יוצא NaN).
  Offset? currentGlobalPosition() {
    if (!_box.attached) return null;
    try {
      final position = _box.localToGlobal(_local);
      return position.isFinite ? position : null;
    } catch (_) {
      return null;
    }
  }

  void addListener(VoidCallback listener) {
    for (final listenable in _scrollListenables) {
      listenable.addListener(listener);
    }
  }

  void removeListener(VoidCallback listener) {
    for (final listenable in _scrollListenables) {
      // ה-ScrollPosition עלול להתחלף/להיסגר בזמן חיי החלונית.
      try {
        listenable.removeListener(listener);
      } catch (_) {}
    }
  }
}
