/// מסגרת בפיקסלים פיזיים, בקואורדינטות מסך.
typedef PhysicalRect = ({int left, int top, int width, int height});

/// מיקום החלון שממנו נפתח חלון חדש, כפי שה-runner מדווח (`windowPlacement`).
///
/// [normal] היא המסגרת ה"רגילה" — גם כשהחלון ממוקסם, ולא מסגרת המיקסום.
class SourceWindowPlacement {
  const SourceWindowPlacement({
    required this.normal,
    required this.workArea,
    required this.maximized,
    this.dpi = 96,
  });

  final PhysicalRect normal;

  /// אזור העבודה של הצג שהחלון יושב בו.
  final PhysicalRect workArea;
  final bool maximized;
  final int dpi;

  /// מפענח את תשובת ה-runner; תשובה חסרה או פגומה → null.
  static SourceWindowPlacement? fromMap(Map<Object?, Object?>? map) {
    if (map == null) return null;
    int? at(String key) => map[key] is int ? map[key] as int : null;
    final values = [
      for (final key in const [
        'left',
        'top',
        'width',
        'height',
        'workLeft',
        'workTop',
        'workWidth',
        'workHeight',
      ])
        at(key),
    ];
    if (values.any((v) => v == null)) return null;
    final v = values.cast<int>();
    if (v[2] <= 0 || v[3] <= 0 || v[6] <= 0 || v[7] <= 0) return null;
    final dpi = at('dpi');
    return SourceWindowPlacement(
      normal: (left: v[0], top: v[1], width: v[2], height: v[3]),
      workArea: (left: v[4], top: v[5], width: v[6], height: v[7]),
      maximized: map['maximized'] == true,
      dpi: (dpi != null && dpi > 0) ? dpi : 96,
    );
  }
}

/// היסט המדרג בפיקסלים לוגיים — בערך גובה שורת כותרת, כמו ב-Windows.
const int kNewWindowCascadeStep = 30;

/// חלון חדש מ-[source]: אותו גודל, מדרג, וחריגה מאזור העבודה חוזרת לפינתו.
/// מקור ממוקסם או במסך מלא → החדש נפתח ממוקסם (ולא במסך מלא).
({PhysicalRect bounds, bool maximized}) cascadeNewWindowPlacement(
  SourceWindowPlacement source, {
  bool fullScreen = false,
}) {
  final work = source.workArea;
  final step = (kNewWindowCascadeStep * source.dpi / 96).round();
  final width = source.normal.width.clamp(1, work.width);
  final height = source.normal.height.clamp(1, work.height);
  final workRight = work.left + work.width;
  final workBottom = work.top + work.height;

  var left = source.normal.left + step;
  var top = source.normal.top + step;
  if (left + width > workRight || top + height > workBottom) {
    left = work.left;
    top = work.top;
  }
  if (left < work.left) left = work.left;
  if (top < work.top) top = work.top;

  return (
    bounds: (left: left, top: top, width: width, height: height),
    maximized: source.maximized || fullScreen,
  );
}
