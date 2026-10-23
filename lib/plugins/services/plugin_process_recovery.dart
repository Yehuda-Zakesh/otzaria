/// גבול ההתאוששות של מופע אחד אחרי נפילת התהליך שלו: לולאת נפילות ב-boot
/// לא תיצור WebView לנצח.
///
/// התקציב נצרך רק כשהמופע מוצג ונוצר מחדש — מופע מוסתר שנפל ממתין עד
/// שיוצג, ולכן נפילה משותפת של כל המופעים לא יוצרת N WebView-ים במקביל.
class PluginProcessRecovery {
  PluginProcessRecovery({
    this.maxRecoveries = 2,
    this.window = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxRecoveries;
  final Duration window;
  final DateTime Function() _clock;
  final List<DateTime> _recoveries = [];

  /// מנסה להשתמש בהתאוששות אחת; false כשהתקציב בחלון נגמר.
  bool consume() {
    final now = _clock();
    _recoveries.removeWhere((at) => now.difference(at) >= window);
    if (_recoveries.length >= maxRecoveries) return false;
    _recoveries.add(now);
    return true;
  }

  /// "נסה שוב" של המשתמש.
  void reset() => _recoveries.clear();
}
