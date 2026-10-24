import 'package:flutter/widgets.dart';

/// מצב גרירת כרטיסיה שמגיעה **מחלון אחר**.
///
/// ⚠️ מחוות העכבר נתפסת אצל חלון המקור, ו-`Draggable`/`DragTarget` של
/// Flutter פועלים רק בתוך חלון אחד. לכן החיווי כאן מוזן מ-`InProcessTabDrops`
/// ולא ממערכת הגרירה של Flutter.
@immutable
class ExternalTabDrag {
  const ExternalTabDrag({
    required this.title,
    required this.local,
  });

  /// כותרת הכרטיסיה הנגררת, לתצוגה בחיווי.
  final String title;

  /// מיקום הסמן בקואורדינטות החלון, בפיקסלים לוגיים.
  ///
  /// ⚠️ ההמרה ממסך לחלון נעשית ב-runner (`ScreenToClient`) ולא כאן:
  /// Flutter אינו יודע היכן החלון שלו יושב על המסך, וחישוב ידני עם DPI היה
  /// ניחוש.
  final Offset local;

  @override
  bool operator ==(Object other) =>
      other is ExternalTabDrag && other.title == title && other.local == local;

  @override
  int get hashCode => Object.hash(title, local);
}

/// מצב הגרירה החיצונית של חלון אחד.
///
/// לא ב-bloc: זהו מצב ויזואלי קצר-חיים של הגרירה, שנעלם בשחרור ואינו
/// נשמר לדיסק. מעבר דרך bloc היה מוסיף אירוע ומצב לכל תזוזת עכבר.
class ExternalTabDragState {
  /// המצב של החלון הראשי; לחלון Dart יש מצב משלו דרך [ExternalTabDragScope].
  static final ExternalTabDragState current = ExternalTabDragState();

  /// המצב של החלון ש-[context] יושב בו; בלי [ExternalTabDragScope] — [current].
  static ExternalTabDragState of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ExternalTabDragScope>()?.state ??
      current;

  /// הגרירה החיצונית הפעילה בחלון הזה, או null כשאין.
  final ValueNotifier<ExternalTabDrag?> drag = ValueNotifier<ExternalTabDrag?>(
    null,
  );

  /// מיקום ההכנסה שהרצועה חישבה עבור הגרירה החיצונית, או null כשהסמן אינו
  /// מעל רצועת הכרטיסיות.
  ///
  /// ⚠️ הרצועה כותבת לכאן ו-`InProcessTabDrops` קורא — לא להפך. רק הרצועה
  /// יודעת היכן הכרטיסיות שלה יושבות על המסך.
  final ValueNotifier<int?> dropIndex = ValueNotifier<int?>(null);
}

/// מצב גרירה חיצונית לחלון אחד, כשכמה חלונות חולקים isolate (חלונות Dart).
class ExternalTabDragScope extends InheritedWidget {
  const ExternalTabDragScope({
    super.key,
    required this.state,
    required super.child,
  });

  final ExternalTabDragState state;

  @override
  bool updateShouldNotify(ExternalTabDragScope oldWidget) =>
      !identical(state, oldWidget.state);
}

/// [ExternalTabDragState.drag] של החלון של ה-isolate הזה.
ValueNotifier<ExternalTabDrag?> get externalTabDrag =>
    ExternalTabDragState.current.drag;

/// [ExternalTabDragState.dropIndex] של החלון של ה-isolate הזה.
ValueNotifier<int?> get externalTabDropIndex =>
    ExternalTabDragState.current.dropIndex;
