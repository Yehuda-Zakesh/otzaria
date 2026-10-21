import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// מצב גרירת כרטיסיה שמגיעה **מחלון אחר**.
///
/// ⚠️ חלון היעד אינו יודע דבר על גרירה שמתרחשת בחלון אחר: הם isolates
/// נפרדים, ומחוות העכבר נתפסת אצל המקור. `Draggable`/`DragTarget` של
/// Flutter פועלים רק בתוך חלון אחד, ולכן החיווי כאן מוזן מהודעות באפיק
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
  /// המיקום נמדד בחלון אחר, ו-Flutter אינו יודע היכן החלון שלו יושב על
  /// המסך. חישוב ידני עם DPI היה ניחוש.
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
  /// המצב של החלון שה-isolate הזה מציג; היום כל חלון הוא isolate משלו.
  static final ExternalTabDragState current = ExternalTabDragState();

  /// הגרירה החיצונית הפעילה בחלון הזה, או null כשאין.
  final ValueNotifier<ExternalTabDrag?> drag = ValueNotifier<ExternalTabDrag?>(
    null,
  );

  /// מיקום ההכנסה שהרצועה חישבה עבור הגרירה החיצונית, או null כשהסמן אינו
  /// מעל רצועת הכרטיסיות.
  ///
  /// ⚠️ הרצועה כותבת לכאן ו-[WindowBusHost] קורא — לא להפך. רק הרצועה
  /// יודעת היכן הכרטיסיות שלה יושבות על המסך, וההודעה מהאפיק נושאת נקודה
  /// גלובלית בלבד.
  final ValueNotifier<int?> dropIndex = ValueNotifier<int?>(null);
}

/// [ExternalTabDragState.drag] של החלון של ה-isolate הזה.
ValueNotifier<ExternalTabDrag?> get externalTabDrag =>
    ExternalTabDragState.current.drag;

/// [ExternalTabDragState.dropIndex] של החלון של ה-isolate הזה.
ValueNotifier<int?> get externalTabDropIndex =>
    ExternalTabDragState.current.dropIndex;
