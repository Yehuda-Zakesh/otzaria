import 'dart:math' as math;

/// שלב עיבוד שקט שאחרי ההורדה (או בתוכה) ושנכלל בזמן הנותר.
enum EtaPhaseKind { hash, join, extract, copy }

/// קצבי ברירת מחדל (בייט/שנייה) לשלב שעדיין לא נמדד בעבודה הנוכחית.
const Map<EtaPhaseKind, double> _defaultPhaseRates = {
  EtaPhaseKind.hash: 150e6,
  EtaPhaseKind.join: 100e6,
  EtaPhaseKind.copy: 100e6,
  EtaPhaseKind.extract: 40e6,
};

/// שלב עיבוד מתוכנן: [id] ייחודי בעבודה, [bytes] כמות העבודה בבייטים.
class EtaPhase {
  const EtaPhase(this.id, this.kind, this.bytes);

  final String id;
  final EtaPhaseKind kind;
  final int bytes;
}

enum EtaStatus {
  /// אין עדיין מספיק נתונים להערכה.
  calculating,

  /// הורדה פעילה עם הערכה.
  estimating,

  /// לא הגיעו בייטים כמה שניות — ממתינים לחיבור.
  stalled,

  /// שלב עיבוד ([EtaReading.phase]) רץ כעת.
  phase,
}

class EtaReading {
  const EtaReading(this.status, this.remaining, [this.phase]);

  final EtaStatus status;

  /// הזמן הנותר המוצג (אחרי שכבת התצוגה), או null כשאין להציגו.
  final Duration? remaining;
  final EtaPhaseKind? phase;
}

/// קצב העברה: סכומים דועכים של בייטים ושל זמן, משוקלל עם הממוצע. שקט אינו
/// נדגם; הדגימה שאחריו מכסה את הפער (תקיעה בודדת: רק 2 שניות ממנו).
class TransferRateEstimator {
  static const double _tau = 8;
  static const double stallSeconds = 5;
  static const double _isolatedStallSeconds = 2;
  static const double restartAfterStallSeconds = 30;

  double _sb = 0;
  double _st = 0;
  double? _lastT;
  int _lastBytes = 0;
  double _activeElapsed = 0;
  int _sessionBytes = 0;
  double _warmElapsed = 0;
  int _warmBytes = 0;
  int _warmSamples = 0;
  double _maxDataGap = 0;
  double? _lastStallRecoveryT;
  double _isolatedStallDeficit = 0;

  /// החימום הושלם; נשאר כך עד איפוס אחרי תקיעה ארוכה.
  bool warmedUp = false;

  /// זמן הנתונים מאז תחילת ההערכה האחרונה (התחלה או תקיעה ארוכה).
  double get warmElapsed => _warmElapsed;
  int get warmBytes => _warmBytes;
  int get warmSamples => _warmSamples;

  /// זמן הנתונים הנדרש לחימום: זרם בפרצים ממתין לכמה מחזורים.
  double get warmSecondsNeeded => math.max(3, math.min(15, 3 * _maxDataGap));

  /// [bytes] — מונה מצטבר של בייטי רשת בלבד; [t] — שניות בשעון מונוטוני.
  void addSample(int bytes, double t) {
    final lastT = _lastT;
    if (lastT == null) return rebaseline(bytes, t);
    final db = bytes - _lastBytes;
    if (db < 0) return rebaseline(bytes, t);
    if (db == 0) return;
    final gap = t - lastT;
    if (gap < 0.05) return;
    if (gap >= restartAfterStallSeconds) {
      // חלון חדש מתחיל בנתונים שחזרו; דגימת ההתאוששות רק קובעת בסיס.
      _sb = _st = 0;
      _warmElapsed = 0;
      _warmBytes = 0;
      _warmSamples = 0;
      _maxDataGap = 0;
      _lastStallRecoveryT = null;
      _isolatedStallDeficit = 0;
      warmedUp = false;
      return rebaseline(bytes, t);
    }
    var dt = gap;
    if (gap >= stallSeconds) {
      // שקט ארוך שחוזר (פרוקסי שמוסר בפרצים) הוא חלק מהקצב; תקיעה בודדת לא.
      final lastRecovery = _lastStallRecoveryT;
      final recurring =
          lastRecovery != null && t - lastRecovery <= restartAfterStallSeconds;
      if (recurring) {
        // התקיעה הקודמת נספרה כבודדת (2 שניות) — משלימים את שאר הפער שלה.
        _st += _isolatedStallDeficit * math.exp(-(t - lastRecovery) / _tau);
        _activeElapsed += _isolatedStallDeficit;
        _warmElapsed += _isolatedStallDeficit;
        _isolatedStallDeficit = 0;
      } else {
        dt = _isolatedStallSeconds;
        _isolatedStallDeficit = gap - _isolatedStallSeconds;
      }
      _lastStallRecoveryT = t;
    }
    _maxDataGap = math.max(_maxDataGap, gap);
    final decay = math.exp(-dt / _tau);
    _sb = _sb * decay + db;
    _st = _st * decay + dt;
    _activeElapsed += dt;
    _sessionBytes += db;
    _warmElapsed += dt;
    _warmBytes += db;
    _warmSamples++;
    _lastT = t;
    _lastBytes = bytes;
  }

  /// הדגימה הבאה תימדד מכאן — הפער שלפניה אינו נהפך לדגימה איטית.
  void rebaseline(int bytes, double t) {
    _lastT = t;
    _lastBytes = bytes;
  }

  /// בייט/שנייה, או null לפני שנמדד דבר.
  double? get rate {
    if (_st <= 0 || _activeElapsed <= 0) return null;
    final emaRate = _sb / _st;
    final avgRate = _sessionBytes / _activeElapsed;
    final w = (_activeElapsed / 60).clamp(0.5, 1.0);
    return w * emaRate + (1 - w) * avgRate;
  }
}

/// שכבת התצוגה: סופרת לאחור בזמן אמת, ומתקנת אל ההערכה הגולמית רק בנקודות
/// תיקון — שנייה של שקט אחרי פרץ נתונים, או זרימה רציפה של 2 שניות לפחות.
class EtaCountdownDisplay {
  static const double _flowGapSeconds = 1;
  static const double _flowSeconds = 2;
  static const double _maxCorrectionSeconds = 30;

  double? _shown;
  double? _lastT;
  double? _lastCorrectionT;
  double? _lastDataT;
  double _flowStartT = 0;
  double _rawAtLastData = 0;
  bool _runOpen = false;

  /// [fresh] — הגיעו נתונים חדשים מאז העדכון הקודם.
  double update(double raw, double t, {required bool fresh}) {
    final shown = _shown;
    final last = _lastT;
    _lastT = t;
    final lastData = _lastDataT;
    double? target;
    if (_runOpen && lastData != null && t - lastData >= _flowGapSeconds) {
      // מסיימים את הפרץ הקודם גם כשכבר הגיעה הדגימה הבאה.
      _runOpen = false;
      target = _rawAtLastData;
    }
    if (fresh) {
      if (lastData == null || t - lastData >= _flowGapSeconds) _flowStartT = t;
      _lastDataT = t;
      _rawAtLastData = raw;
      _runOpen = true;
    }
    if (shown == null || last == null) {
      _lastCorrectionT = t;
      return _shown = raw;
    }
    var next = shown - (t - last);
    if (fresh && t - _flowStartT >= _flowSeconds) target = raw;
    if (target != null) {
      final cdt = math.min(t - (_lastCorrectionT ?? t), _maxCorrectionSeconds);
      _lastCorrectionT = t;
      if (target < next * 0.5) {
        next = target;
      } else {
        final diff = target - next;
        final outsideBand = diff.abs() > math.max(5, next * 0.10);
        final tau = !outsideBand ? 30 : (diff < 0 ? 3 : 12);
        next += (1 - math.exp(-cdt / tau)) * diff;
      }
    }
    return _shown = math.max(next, 0);
  }

  /// הזמן שעובר עד העדכון הבא אינו נספר לאחור (תקיעה, השהיה: התצוגה קפואה).
  void freeze(double t) {
    _lastT = t;
    _runOpen = false;
  }

  double? get shown => _shown;

  void reset() {
    _shown = null;
    _lastT = null;
    _lastCorrectionT = null;
    _runOpen = false;
  }
}

/// זמן נותר לעבודת הורדה אחת, כולל שלבי העיבוד שאחריה. בייטים שלא הגיעו
/// מהרשת (דיווח ראשון אחרי [pause], מונה שחזר אחורה, קפיצה חריגה) רק מקטינים את הנותר.
class DownloadEtaEstimator {
  DownloadEtaEstimator({
    Duration Function()? clock,
    this.maxNetworkChunkBytes = 8 * 1024 * 1024,
  }) : _clock = clock ?? _stopwatchClock();

  final Duration Function() _clock;
  final int maxNetworkChunkBytes;
  final TransferRateEstimator _rate = TransferRateEstimator();

  int _downloaded = 0;
  int _total = 0;
  int? _lastReported;
  int _networkBytes = 0;
  bool _paused = true;
  double _lastActivityT = 0;
  bool _newData = false;

  final List<EtaPhase> _plan = [];
  _RunningPhase? _phase;
  final Map<EtaPhaseKind, double> _measuredBytes = {};
  final Map<EtaPhaseKind, double> _measuredSecs = {};

  final EtaCountdownDisplay _display = EtaCountdownDisplay();

  String? _text;
  double _textT = 0;
  EtaStatus? _textStatus;
  EtaPhaseKind? _textPhase;
  Duration? _textRemaining;

  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  double get _now => _clock().inMicroseconds / 1e6;

  /// שלב שקט ידוע (חיבור, מעבר בין קבצים, ניסיון חוזר): אין דגימות ואין
  /// תקיעה עד הדיווח הבא, שנקבע כבסיס חדש.
  void pause() => _paused = true;

  void addProgress(int downloadedBytes, int totalBytes) {
    final t = _now;
    _downloaded = downloadedBytes;
    _total = totalBytes;
    _newData = true;
    final last = _lastReported;
    _lastReported = downloadedBytes;
    final delta = last == null ? -1 : downloadedBytes - last;
    if (_paused || delta < 0 || delta > maxNetworkChunkBytes) {
      _paused = false;
      _lastActivityT = t;
      _rate.rebaseline(_networkBytes, t);
      return;
    }
    if (delta == 0) return;
    _networkBytes += delta;
    _lastActivityT = t;
    _rate.addSample(_networkBytes, t);
  }

  /// כל ההורדה הסתיימה (גם אם נכס אופציונלי דולג).
  void finishDownload() {
    _downloaded = _total;
    _lastReported ??= _total;
    _paused = true;
    _newData = true;
  }

  void planPhases(Iterable<EtaPhase> phases) => _plan.addAll(phases);

  void dropPhase(String id) => _plan.removeWhere((p) => p.id == id);

  /// [tracksProgress] = false: שלב בלי דיווחי התקדמות — נספר לאחור מההערכה.
  void startPhase(EtaPhase phase, {bool tracksProgress = true}) {
    endPhase();
    dropPhase(phase.id);
    _paused = true;
    _newData = true;
    _phase = _RunningPhase(phase, _now, tracksProgress);
  }

  void phaseProgress(int processedBytes) {
    final running = _phase;
    if (running == null) return;
    running.processed = processedBytes;
    _newData = true;
  }

  void endPhase() {
    final running = _phase;
    if (running == null) return;
    _phase = null;
    _newData = true;
    final secs = _now - running.startedT;
    // שלב שאינו מדווח נמדד רק כשנמשך די זמן — אחרת "שלב" מיידי מנפח את הקצב.
    if (!running.tracksProgress && secs < 1) return;
    final kind = running.phase.kind;
    _measuredBytes[kind] =
        (_measuredBytes[kind] ?? 0) +
        (running.tracksProgress ? running.processed : running.phase.bytes);
    _measuredSecs[kind] = (_measuredSecs[kind] ?? 0) + secs;
  }

  double _phaseRate(EtaPhaseKind kind, double t) {
    var bytes = _measuredBytes[kind] ?? 0;
    var secs = _measuredSecs[kind] ?? 0;
    final running = _phase;
    if (running != null &&
        running.tracksProgress &&
        running.phase.kind == kind) {
      bytes += running.processed;
      secs += t - running.startedT;
    }
    if (secs >= 1 && bytes > 0) return bytes / secs;
    return _defaultPhaseRates[kind]!;
  }

  // תקיעה בודדת מגדילה את הפער המרבי — אסור שתחזיר "מחשב" אחרי שהחימום הושלם.
  bool _warmedUp(int remaining) => _rate.warmedUp =
      _rate.warmedUp ||
      (_rate.warmElapsed >= _rate.warmSecondsNeeded &&
          _rate.warmSamples >= 3 &&
          _rate.warmBytes >= math.min(1024 * 1024, remaining * 0.01));

  /// מצב ההערכה כעת; מעדכן את שכבת התצוגה (ספירה לאחור והיסטרזיס).
  EtaReading read() => _lastReading = _read();

  EtaReading _read() {
    final t = _now;
    final remainingDownload = math.max(_total - _downloaded, 0);
    final running = _phase;
    final hasNewData = _newData;
    _newData = false;

    // לפני הדיווח הראשון (התחברות) אין עדיין מה להעריך.
    if (_lastReported == null && running == null) {
      _display.reset();
      return const EtaReading(EtaStatus.calculating, null);
    }

    if (running == null && !_paused && remainingDownload > 0) {
      final silence = t - _lastActivityT;
      if (silence >= TransferRateEstimator.stallSeconds) {
        _display.freeze(t);
        if (silence >= TransferRateEstimator.restartAfterStallSeconds) {
          _display.reset();
        }
        return const EtaReading(EtaStatus.stalled, null);
      }
    }

    double? raw;
    final rate = _rate.rate;
    if (remainingDownload == 0) {
      raw = 0;
    } else if (rate != null && rate > 0 && _warmedUp(remainingDownload)) {
      raw = remainingDownload / rate;
    }
    if (raw != null) {
      if (running != null) {
        final phaseRate = _phaseRate(running.phase.kind, t);
        raw += running.tracksProgress
            ? math.max(running.phase.bytes - running.processed, 0) / phaseRate
            : math.max(
                running.phase.bytes / phaseRate - (t - running.startedT),
                0,
              );
      }
      for (final phase in _plan) {
        raw = raw! + phase.bytes / _phaseRate(phase.kind, t);
      }
    }

    final status = running != null
        ? EtaStatus.phase
        : raw == null
        ? EtaStatus.calculating
        : EtaStatus.estimating;
    if (raw == null) {
      _display.reset();
      return EtaReading(status, null, running?.phase.kind);
    }
    // השהיה ידועה שאינה שלב מוערך: התצוגה קפואה, כמו בתקיעה.
    final frozen = _display.shown;
    final double shown;
    if (_paused && running == null && frozen != null) {
      _display.freeze(t);
      shown = frozen;
    } else {
      shown = _display.update(raw, t, fresh: hasNewData);
    }
    return EtaReading(
      status,
      Duration(microseconds: (shown * 1e6).round()),
      running?.phase.kind,
    );
  }

  /// הקריאה האחרונה של [read].
  EtaReading get lastReading => _lastReading;
  EtaReading _lastReading = const EtaReading(EtaStatus.calculating, null);

  /// שורות הסטטוס לתצוגה; טקסט הזמן מתחלף לכל היותר פעם בשנייה, ושינוי מצב
  /// מוצג מיד. null כשאין מה להציג.
  String? statusText() {
    final reading = read();
    final t = _now;
    if (_textStatus == reading.status &&
        _textPhase == reading.phase &&
        t - _textT < 1) {
      return _text;
    }
    _textStatus = reading.status;
    _textPhase = reading.phase;
    _textT = t;
    _textRemaining = reading.remaining;
    return _text = _composeText(reading);
  }

  /// הזמן שמאחורי הטקסט המוצג כעת (null כשאין בו זמן).
  Duration? get textRemaining => _textRemaining;
}

String? _composeText(EtaReading reading) {
  final remaining = reading.remaining;
  final etaLine = remaining == null
      ? null
      : formatRemainingTimeHebrew(remaining);
  switch (reading.status) {
    case EtaStatus.calculating:
      return 'מחשב את הזמן הנותר…';
    case EtaStatus.stalled:
      return 'ממתין לחיבור…';
    case EtaStatus.estimating:
      return etaLine;
    case EtaStatus.phase:
      final label = switch (reading.phase) {
        EtaPhaseKind.hash => 'מאמת את הקובץ…',
        EtaPhaseKind.join => 'מחבר חלקים…',
        _ => null,
      };
      final lines = [?label, ?etaLine];
      return lines.isEmpty ? null : lines.join('\n');
  }
}

class _RunningPhase {
  _RunningPhase(this.phase, this.startedT, this.tracksProgress);

  final EtaPhase phase;
  final double startedT;
  final bool tracksProgress;
  int processed = 0;
}

/// הזמן הנותר בשניות אחרי עיגול התצוגה: 0 (= "כמה שניות") מתחת ל-5 שניות,
/// ומעל זה לפי דלי הערך הגולמי — 5 שניות, 10 שניות, דקה, ו-5 דקות מעל שעה.
int roundedRemainingSeconds(Duration d) {
  final s = d.inMicroseconds / 1e6;
  if (s < 5) return 0;
  if (s < 60) return (s / 5).round() * 5;
  if (s < 600) return (s / 10).round() * 10;
  if (s < 3600) return (s / 60).round() * 60;
  return (s / 300).round() * 300;
}

/// מעצב זמן נותר לטקסט עברי, למשל "נותרו כ-7 דקות ו-30 שניות". מעגלים לפי
/// דלי הערך הגולמי ומעצבים לפי הערך המעוגל (59 שניות → "נותרה כדקה").
String formatRemainingTimeHebrew(Duration d) {
  final rounded = roundedRemainingSeconds(d);
  if (rounded == 0) return 'עוד כמה שניות';
  if (rounded < 60) return 'נותרו כ-$rounded שניות';
  if (rounded < 3600) {
    final minutes = rounded ~/ 60;
    final seconds = rounded % 60;
    return _remainingHebrew(
      minutes == 1 ? 'דקה' : '$minutes דקות',
      seconds == 0 ? null : '$seconds שניות',
    );
  }
  final hours = rounded ~/ 3600;
  final minutes = (rounded % 3600) ~/ 60;
  return _remainingHebrew(switch (hours) {
    1 => 'שעה',
    2 => 'שעתיים',
    _ => '$hours שעות',
  }, minutes == 0 ? null : '$minutes דקות');
}

/// "כ" צמודה למילה ו"כ-" לפני ספרה; "נותרה" רק ל"דקה"/"שעה" לבדן.
String _remainingHebrew(String lead, String? tail) {
  final first = lead.codeUnitAt(0);
  final startsWithDigit = first >= 0x30 && first <= 0x39;
  final verb = tail == null && (lead == 'דקה' || lead == 'שעה')
      ? 'נותרה'
      : 'נותרו';
  final amount = tail == null ? lead : '$lead ו-$tail';
  return startsWithDigit ? '$verb כ-$amount' : '$verb כ$amount';
}
