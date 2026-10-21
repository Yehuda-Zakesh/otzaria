import 'package:flutter/material.dart';
import 'package:otzaria/tour/tour_target_keys.dart';

/// עוטף את חלונית הניווט של ספר טקסט במפתח יציב, ומפרסם אותו כיעד לסיור
/// המודרך ב-[TourTargetKeys.activeTextBookNavPanel] של החלון כל עוד
/// [isActiveTab] נכון.
///
/// עטיפה שמתווספת ונעלמת לפי [isActiveTab] הייתה מחליפה את מבנה העץ באותו
/// מקום, ו-Flutter משמיד אז את כל תת-העץ — החיפוש והניווט אובדים בכל מעבר טאב.
class TextBookNavPanelTourTarget extends StatefulWidget {
  /// האם זה הטאב הפעיל, כלומר זו החלונית שהסיור המודרך צריך להדגיש.
  final bool isActiveTab;

  final Widget child;

  const TextBookNavPanelTourTarget({
    super.key,
    required this.isActiveTab,
    required this.child,
  });

  @override
  State<TextBookNavPanelTourTarget> createState() =>
      _TextBookNavPanelTourTargetState();
}

class _TextBookNavPanelTourTargetState
    extends State<TextBookNavPanelTourTarget> {
  final GlobalKey _paneKey = GlobalKey(
    debugLabel: 'text_book_nav_panel_tour_target',
  );

  /// נשמר ב-initState: ב-dispose כבר אסור לחפש ב-context.
  late final TourTargetKeys _tour;

  @override
  void initState() {
    super.initState();
    _tour = TourTargetKeys.of(context);
    _syncTourTarget();
  }

  @override
  void didUpdateWidget(covariant TextBookNavPanelTourTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTourTarget();
  }

  @override
  void dispose() {
    if (_tour.activeTextBookNavPanel == _paneKey) {
      _tour.activeTextBookNavPanel = null;
    }
    super.dispose();
  }

  /// הניקוי מותנה בבעלות על הפרסום, כדי שלא יימחק פרסום של טאב אחר — הטאב
  /// הנכנס והיוצא מתעדכנים באותו frame ובסדר לא מובטח.
  void _syncTourTarget() {
    if (widget.isActiveTab) {
      _tour.activeTextBookNavPanel = _paneKey;
    } else if (_tour.activeTextBookNavPanel == _paneKey) {
      _tour.activeTextBookNavPanel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _paneKey, child: widget.child);
  }
}
