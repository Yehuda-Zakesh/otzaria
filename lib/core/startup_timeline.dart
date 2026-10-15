import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';

/// ציר הזמן של עליית התוכנה, מ-`main()` ועד חשיפת החלון הראשי.
///
/// החלון הראשי מוסתר עד `presentMainWindow`, ורשת הביטחון של המסך הראשי
/// מתחילה רק אחרי הבוטסטרפ — עלייה איטית נראית למשתמש כסמל צף בלבד, ובלי
/// הרשומה הזו ב-errors.txt אין דרך לדעת איזה שלב עיכב אותה (issue #1192).
class StartupTimeline {
  StartupTimeline({
    void Function(String text)? sink,
    this.slowThreshold = const Duration(seconds: 20),
  }) : _sink = sink ?? ErrorLogFile.appendText;

  static final StartupTimeline instance = StartupTimeline();

  /// עלייה שנמשכה פחות מזה אינה נרשמת — errors.txt נשאר יומן של תקלות בלבד.
  final Duration slowThreshold;

  final void Function(String text) _sink;
  final Stopwatch _clock = Stopwatch();
  final List<_Phase> _phases = [];
  final List<_Mark> _marks = [];
  bool _reported = false;
  Timer? _stallWatch;
  int _lastTickMs = 0;

  /// טיימר שמאחר ביותר מזה נחשב לקיפאון של ה-isolate הראשי ונרשם כציון.
  static const Duration stallThreshold = Duration(seconds: 1);
  static const Duration _stallTick = Duration(milliseconds: 250);

  /// מתחיל את השעון ואת מזהה הקיפאון. קריאה חוזרת אינה מאפסת אותם.
  void start() {
    if (_clock.isRunning || _clock.elapsedTicks != 0) return;
    _clock.start();
    // ציר הזמן מראה מתי חלון של קוד רץ, לא מה חסם בין לבין; טיימר שמאחר
    // חושף חסימה סינכרונית ומתי היא קרתה, גם אם איש לא עטף אותה בפאזה.
    _lastTickMs = 0;
    _stallWatch = Timer.periodic(_stallTick, (_) {
      final now = elapsedMs;
      final gap = now - _lastTickMs - _stallTick.inMilliseconds;
      if (gap >= stallThreshold.inMilliseconds) {
        _marks.add(_Mark('stall:${gap}ms', _lastTickMs));
      }
      _lastTickMs = now;
    });
  }

  int get elapsedMs => _clock.elapsedMilliseconds;

  /// מריץ שלב עלייה ורושם את משכו. חריגה עוברת הלאה; המשך נרשם גם אז.
  Future<T> phase<T>(String name, Future<T> Function() body) async {
    final startedAt = elapsedMs;
    try {
      return await body();
    } finally {
      _phases.add(_Phase(name, startedAt, elapsedMs - startedAt));
    }
  }

  /// שלב סינכרוני — בנאי כבד שרץ בתוך build ואי אפשר להמתין לו.
  T phaseSync<T>(String name, T Function() body) {
    final startedAt = elapsedMs;
    try {
      return body();
    } finally {
      _phases.add(_Phase(name, startedAt, elapsedMs - startedAt));
    }
  }

  /// נקודת ציון ללא משך — למשל "הבוטסטרפ הסתיים" או "חשיפה דרך רשת הביטחון".
  /// אחרי החשיפה הציונים נזרקים: הרשומה כבר נכתבה, ואין טעם לצבור זיכרון.
  void mark(String name) {
    if (_reported) return;
    _marks.add(_Mark(name, elapsedMs));
  }

  /// כמו [mark], אך רק בפעם הראשונה — לנקודות שחוזרות בכל build.
  /// היציאה המוקדמת חוסכת סריקה של הרשימה בכל בנייה אחרי החשיפה.
  void markOnce(String name) {
    if (_reported) return;
    if (_marks.any((mark) => mark.name == name)) return;
    mark(name);
  }

  /// נקרא בחשיפת החלון הראשי. רושם ללוג רק אם העלייה חרגה מ-[slowThreshold].
  /// הקריאה הראשונה בלבד נחשבת — הפעלה מחדש של העץ אינה רושמת שוב.
  void finishAtReveal({DateTime? now, String? version}) {
    if (_reported) return;
    _reported = true;
    _clock.stop();
    _stallWatch?.cancel();
    _stallWatch = null;
    if (_clock.elapsed < slowThreshold) return;
    try {
      _sink(format(now: now, version: version));
    } catch (error) {
      debugPrint('⚠️ רישום ציר הזמן של העלייה נכשל: $error');
    }
  }

  /// Structured copy of the timeline, for developer diagnostics output.
  Map<String, Object?> toJson() => {
    'revealMs': _reported ? _clock.elapsedMilliseconds : null,
    'phases': [
      for (final phase in _phases)
        {
          'name': phase.name,
          'atMs': phase.startedAtMs,
          'durationMs': phase.durationMs,
        },
    ],
    'marks': [
      for (final mark in _marks) {'name': mark.name, 'atMs': mark.atMs},
    ],
  };

  /// הרשומה כפי שתיכתב ל-errors.txt.
  String format({DateTime? now, String? version}) {
    final buffer = StringBuffer()
      ..writeln(
        '=== Slow startup ${(now ?? DateTime.now()).toIso8601String()} ===',
      )
      ..writeln('Version: ${version ?? ErrorLogFile.appVersion}')
      ..writeln('Window shown after: ${_clock.elapsedMilliseconds}ms')
      ..writeln(
        'Measured from Dart main(); native/engine startup before it is not '
        'included. A gap between one phase end and the next start is time '
        'spent outside the measured phases.',
      )
      ..writeln('Phases (start → duration):');
    for (final phase in _phases) {
      buffer.writeln(
        '  ${phase.name}: @${phase.startedAtMs}ms ${phase.durationMs}ms',
      );
    }
    if (_marks.isNotEmpty) {
      buffer.writeln('Marks:');
      for (final mark in _marks) {
        buffer.writeln('  ${mark.name}: @${mark.atMs}ms');
      }
    }
    buffer.writeln();
    return buffer.toString();
  }
}

class _Phase {
  const _Phase(this.name, this.startedAtMs, this.durationMs);
  final String name;
  final int startedAtMs;
  final int durationMs;
}

class _Mark {
  const _Mark(this.name, this.atMs);
  final String name;
  final int atMs;
}
