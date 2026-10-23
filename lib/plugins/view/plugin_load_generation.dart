/// דור הטעינה של דף תוסף. כל ניווט או טעינה מחדש פותחים דור חדש, ושלב של
/// זרימת boot מדור ישן — שעדיין ממתינה, למשל לגופנים — אינו נוגע בדף החדש.
class PluginLoadGeneration {
  int _current = 0;

  /// נקרא ב-onLoadStart: הזרימה הפעילה, אם יש, כבר אינה של הדף הנוכחי.
  void invalidate() => _current++;

  /// נקרא בתחילת onLoadStop, ומחזיר את הדור של הזרימה שמתחילה.
  int begin() => ++_current;

  bool isCurrent(int generation) => generation == _current;
}
