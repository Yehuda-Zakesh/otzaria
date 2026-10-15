// מקליט עדכוני סמנטיקה — בדיוק מה שהמסגרת שולחת למנוע — ובודק את
// האינווריאנט שגשר הנגישות של Windows (accessibility_bridge.cc / ui::AXTree)
// אוכף על כל עדכון:
//
// * כל צומת בעדכון הוא השורש, או מופיע ב-childrenInTraversalOrder של צומת
//   אחר בעדכון, או כבר קיים בעץ ואביו אינו בעדכון. אחרת המנוע רושם
//   `N will not be in the tree and is not the new root` ודוחה את העדכון כולו.
// * כל ילד שצומת בעדכון מצהיר עליו חייב להיות בעדכון או כבר בעץ. אחרת
//   `Nodes left pending by the update`.
//
// עדכון שנדחה משאיר את עץ הנגישות של Windows קפוא, ובהמשך התוכנה קורסת
// (issue #1399). הכלי נותן לבדיקת widget רגילה, בלי קורא מסך, לתפוס את
// העדכון הפגום ברגע שהוא נשלח.
//
// שימוש: בקובץ הבדיקה, לפני `testWidgets`, ליצור את ה-binding —
// `SemanticsRecordingBinding.ensure()` — ולהפעיל סמנטיקה עם
// `tester.ensureSemantics()`. אחרי הפעולה הנבדקת, `recorder.violations` ריק
// פירושו שכל העדכונים היו תקינים.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// צומת כפי שנשלח למנוע בקריאת `updateNode` אחת.
class RecordedSemanticsNode {
  RecordedSemanticsNode({
    required this.id,
    required this.label,
    required this.tooltip,
    required this.traversalParent,
    required this.childrenInTraversalOrder,
  });

  final int id;
  final String label;
  final String tooltip;

  /// מזהה האב בסדר המעבר, או -1 כשאין (כפי שנשלח למנוע).
  final int traversalParent;
  final List<int> childrenInTraversalOrder;

  @override
  String toString() =>
      'SemanticsNode#$id label="$label" tooltip="$tooltip" '
      'traversalParent=$traversalParent children=$childrenInTraversalOrder';
}

/// עדכון אחד שהמנוע היה דוחה, והסיבה במילותיו.
class SemanticsUpdateViolation {
  SemanticsUpdateViolation(this.updateIndex, this.message, this.node);

  /// מספרו הסידורי של העדכון מתחילת ההקלטה (החל מ-1).
  final int updateIndex;
  final String message;
  final RecordedSemanticsNode node;

  @override
  String toString() => '[update $updateIndex] $message\n    $node';
}

/// מודל העץ כפי שהמנוע רואה אותו — ילדים בסדר מעבר בלבד, כמו הגשר.
class SemanticsUpdateRecorder {
  final Map<int, List<int>> _children = {};
  final Map<int, int> _parentOf = {};
  int _updates = 0;

  /// כל העדכונים שנדחו היו נדחים על ידי המנוע.
  final List<SemanticsUpdateViolation> violations = [];

  /// מנקה את המודל ואת הממצאים — לתחילת תרחיש חדש באותו קובץ בדיקה.
  void reset() {
    _children.clear();
    _parentOf.clear();
    _updates = 0;
    violations.clear();
  }

  void _apply(List<RecordedSemanticsNode> update) {
    _updates++;
    final ids = {for (final n in update) n.id};
    final claimed = <int>{};
    for (final n in update) {
      claimed.addAll(n.childrenInTraversalOrder);
    }
    var accepted = true;
    for (final n in update) {
      if (n.id == 0) continue; // השורש
      if (claimed.contains(n.id)) continue;
      final knownParent = _parentOf[n.id];
      if (knownParent != null && !ids.contains(knownParent)) continue;
      accepted = false;
      violations.add(
        SemanticsUpdateViolation(
          _updates,
          '${n.id} will not be in the tree and is not the new root '
          '(אף צומת בעדכון אינו מצהיר עליו כילד)',
          n,
        ),
      );
    }
    for (final n in update) {
      for (final child in n.childrenInTraversalOrder) {
        if (child != 0 &&
            !ids.contains(child) &&
            !_parentOf.containsKey(child)) {
          accepted = false;
          violations.add(
            SemanticsUpdateViolation(
              _updates,
              'Nodes left pending by the update: $child '
              '(הוצהר כילד של ${n.id} אך אינו בעדכון ולא בעץ)',
              n,
            ),
          );
        }
      }
    }
    // המנוע דוחה עדכון פגום בשלמותו; העץ שלו נשאר כפי שהיה.
    if (!accepted) return;
    for (final n in update) {
      final previous = _children[n.id];
      if (previous != null) {
        for (final child in previous) {
          if (_parentOf[child] == n.id &&
              !n.childrenInTraversalOrder.contains(child)) {
            _removeSubtree(child);
          }
        }
      }
      _children[n.id] = List.of(n.childrenInTraversalOrder);
      for (final child in n.childrenInTraversalOrder) {
        _parentOf[child] = n.id;
      }
    }
  }

  void _removeSubtree(int id) {
    _parentOf.remove(id);
    final kids = _children.remove(id);
    if (kids == null) return;
    for (final kid in kids) {
      if (_parentOf[kid] == id) _removeSubtree(kid);
    }
  }
}

/// ה-builder של המסגרת, עטוף: מתעד כל `updateNode` ומעביר הלאה כרגיל.
class _RecordingSemanticsUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingSemanticsUpdateBuilder(this._inner, this._recorder);

  final ui.SemanticsUpdateBuilder _inner;
  final SemanticsUpdateRecorder _recorder;
  final List<RecordedSemanticsNode> _nodes = [];

  @override
  void updateNode({
    required int id,
    required ui.SemanticsFlags flags,
    required int actions,
    required int maxValueLength,
    required int currentValueLength,
    required int textSelectionBase,
    required int textSelectionExtent,
    required int platformViewId,
    required int scrollChildren,
    required int scrollIndex,
    required int traversalParent,
    required double scrollPosition,
    required double scrollExtentMax,
    required double scrollExtentMin,
    required ui.Rect rect,
    required String identifier,
    required String label,
    required List<ui.StringAttribute> labelAttributes,
    required String value,
    required List<ui.StringAttribute> valueAttributes,
    required String increasedValue,
    required List<ui.StringAttribute> increasedValueAttributes,
    required String decreasedValue,
    required List<ui.StringAttribute> decreasedValueAttributes,
    required String hint,
    required List<ui.StringAttribute> hintAttributes,
    required String tooltip,
    required ui.TextDirection? textDirection,
    required Float64List transform,
    required Float64List hitTestTransform,
    required Int32List childrenInTraversalOrder,
    required Int32List childrenInHitTestOrder,
    required Int32List additionalActions,
    int headingLevel = 0,
    String linkUrl = '',
    ui.SemanticsRole role = ui.SemanticsRole.none,
    required List<String>? controlsNodes,
    ui.SemanticsValidationResult validationResult =
        ui.SemanticsValidationResult.none,
    ui.SemanticsHitTestBehavior hitTestBehavior =
        ui.SemanticsHitTestBehavior.defer,
    required ui.SemanticsInputType inputType,
    required ui.Locale? locale,
    required String minValue,
    required String maxValue,
  }) {
    _nodes.add(
      RecordedSemanticsNode(
        id: id,
        label: label,
        tooltip: tooltip,
        traversalParent: traversalParent,
        childrenInTraversalOrder: List<int>.from(childrenInTraversalOrder),
      ),
    );
    _inner.updateNode(
      id: id,
      flags: flags,
      actions: actions,
      maxValueLength: maxValueLength,
      currentValueLength: currentValueLength,
      textSelectionBase: textSelectionBase,
      textSelectionExtent: textSelectionExtent,
      platformViewId: platformViewId,
      scrollChildren: scrollChildren,
      scrollIndex: scrollIndex,
      traversalParent: traversalParent,
      scrollPosition: scrollPosition,
      scrollExtentMax: scrollExtentMax,
      scrollExtentMin: scrollExtentMin,
      rect: rect,
      identifier: identifier,
      label: label,
      labelAttributes: labelAttributes,
      value: value,
      valueAttributes: valueAttributes,
      increasedValue: increasedValue,
      increasedValueAttributes: increasedValueAttributes,
      decreasedValue: decreasedValue,
      decreasedValueAttributes: decreasedValueAttributes,
      hint: hint,
      hintAttributes: hintAttributes,
      tooltip: tooltip,
      textDirection: textDirection,
      transform: transform,
      hitTestTransform: hitTestTransform,
      childrenInTraversalOrder: childrenInTraversalOrder,
      childrenInHitTestOrder: childrenInHitTestOrder,
      additionalActions: additionalActions,
      headingLevel: headingLevel,
      linkUrl: linkUrl,
      role: role,
      controlsNodes: controlsNodes,
      validationResult: validationResult,
      hitTestBehavior: hitTestBehavior,
      inputType: inputType,
      locale: locale,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  @override
  void updateCustomAction({
    required int id,
    String? label,
    String? hint,
    int overrideId = -1,
  }) => _inner.updateCustomAction(
    id: id,
    label: label,
    hint: hint,
    overrideId: overrideId,
  );

  @override
  ui.SemanticsUpdate build() {
    _recorder._apply(List.of(_nodes));
    _nodes.clear();
    return _inner.build();
  }
}

/// binding לבדיקות שמקליט את עדכוני הסמנטיקה דרך [recorder].
///
/// חייב להיווצר לפני `testWidgets` הראשון בקובץ (הבינדינג נקבע פעם אחת
/// לאיזולט): `SemanticsRecordingBinding.ensure();` בתחילת `main`.
class SemanticsRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  SemanticsRecordingBinding._();

  /// המקליט המשותף לכל הבדיקות בקובץ.
  static final SemanticsUpdateRecorder recorder = SemanticsUpdateRecorder();

  static SemanticsRecordingBinding? _instance;

  /// יוצר את ה-binding אם עוד לא נוצר, ומחזיר אותו.
  static SemanticsRecordingBinding ensure() =>
      _instance ??= SemanticsRecordingBinding._();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingSemanticsUpdateBuilder(
        super.createSemanticsUpdateBuilder(),
        recorder,
      );
}
