import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/download_eta_estimator.dart';

const _mb = 1000 * 1000;

/// מעריך עם שעון מזויף. כמו בבלוק: קריאה אחרי כל דיווח, וטיימר של שנייה בשקט.
class _Harness {
  _Harness([this._total = 1000 * _mb]) {
    estimator = DownloadEtaEstimator(clock: () => now);
  }

  final int _total;
  late final DownloadEtaEstimator estimator;
  Duration now = Duration.zero;
  int bytes = 0;

  /// הקצב האמיתי הנוכחי, לחישוב הזמן הנותר המדויק.
  int trueRate = 10 * _mb;

  void advance(Duration d) => now += d;

  void report(int value) {
    bytes = value;
    estimator.addProgress(bytes, _total);
    estimator.statusText();
  }

  void feed({required double seconds, int? bytesPerSecond}) {
    if (bytesPerSecond != null) trueRate = bytesPerSecond;
    final steps = (seconds * 10).round();
    for (var i = 0; i < steps; i++) {
      advance(const Duration(milliseconds: 100));
      report(bytes + trueRate ~/ 10);
    }
  }

  /// שקט בלי בייטים; מחזיר את הזמנים שהוצגו בתקתוקי הטיימר.
  List<EtaReading> silence(int seconds) => [
    for (var i = 0; i < seconds; i++) ...[
      () {
        advance(const Duration(seconds: 1));
        return read();
      }(),
    ],
  ];

  EtaReading read() => estimator.read();

  double get etaSeconds => read().remaining!.inMicroseconds / 1e6;

  double get exactEta => (_total - bytes) / trueRate;
}

/// מזרים פרצים: [dataSeconds] של נתונים (צ'אנק כל 100ms) ואז פער של
/// [silenceSeconds] בין דגימות, בממוצע [avgRate]; מחזיר את הקצב בסוף כל פרץ.
List<double> _burstyRates({
  required double dataSeconds,
  required double silenceSeconds,
  required double avgRate,
  int cycles = 40,
}) {
  const interval = 0.1;
  final chunksPerBurst = (dataSeconds / interval).round();
  final rate = TransferRateEstimator();
  final cycle = (chunksPerBurst - 1) * interval + silenceSeconds;
  final chunk = (avgRate * cycle / chunksPerBurst).round();
  var t = 0.0;
  var bytes = 0;
  rate.addSample(0, 0);
  final measured = <double>[];
  for (var c = 0; c < cycles; c++) {
    for (var i = 0; i < chunksPerBurst; i++) {
      t += interval;
      rate.addSample(bytes += chunk, t);
    }
    if (c >= cycles ~/ 2) measured.add(rate.rate!);
    t += silenceSeconds - interval;
  }
  return measured;
}

/// צ'אנק רשת: זמן הגעה (ms) ומספר בייטים.
typedef _Chunk = ({int ms, int bytes});

/// זרם יציב: צ'אנק כל 100ms בקצב [rate] עם רעש אקראי (זרע קבוע) של ±[jitter].
List<_Chunk> _steady({
  required int totalBytes,
  required int rate,
  double jitter = 0,
}) {
  final random = math.Random(7);
  final chunks = <_Chunk>[];
  var sent = 0;
  for (var ms = 100; sent < totalBytes; ms += 100) {
    final factor = 1 + jitter * (2 * random.nextDouble() - 1);
    final bytes = math.min((rate / 10 * factor).round(), totalBytes - sent);
    chunks.add((ms: ms, bytes: bytes));
    sent += bytes;
  }
  return chunks;
}

/// פרצים בממוצע 5MB/s: [onChunks] צ'אנקים במרווח 100ms, ואז פער של
/// [offSeconds] (במחזוריות) עד הצ'אנק הבא — הפער כפי שהמעריך רואה אותו.
List<_Chunk> _bursty({
  required List<double> offSeconds,
  int onChunks = 6,
  int totalBytes = 2000 * _mb,
}) {
  final meanOff = offSeconds.reduce((a, b) => a + b) / offSeconds.length;
  final cycle = (onChunks - 1) * 0.1 + meanOff;
  final chunkBytes = (5 * _mb * cycle / onChunks).round();
  final chunks = <_Chunk>[];
  var sent = 0;
  var ms = 0;
  for (var c = 0; sent < totalBytes; c++) {
    ms += (offSeconds[c % offSeconds.length] * 1000).round();
    for (var i = 0; i < onChunks && sent < totalBytes; i++) {
      if (i > 0) ms += 100;
      final bytes = math.min(chunkBytes, totalBytes - sent);
      chunks.add((ms: ms, bytes: bytes));
      sent += bytes;
    }
  }
  return chunks;
}

/// מקטעים של (שניות, קצב); קצב 0 = שקט. המקטע האחרון נמשך עד הסוף.
List<_Chunk> _segments(List<(int, int)> segments, int totalBytes) {
  final chunks = <_Chunk>[];
  var sent = 0;
  var start = 0;
  for (final (seconds, rate) in segments) {
    final end = start + seconds * 1000;
    for (var ms = start + 100; ms <= end && sent < totalBytes; ms += 100) {
      if (rate == 0) continue;
      final bytes = math.min(rate ~/ 10, totalBytes - sent);
      chunks.add((ms: ms, bytes: bytes));
      sent += bytes;
    }
    start = end;
  }
  return chunks;
}

typedef _Record = ({double t, double? shown, EtaStatus status});

class _Run {
  _Run(this.records, this.texts, this.tEnd);

  final List<_Record> records;

  /// (זמן, ערך מעוגל) בכל החלפת טקסט שיש בו זמן.
  final List<(double, int)> texts;
  final double tEnd;

  double? get firstShownT =>
      records.where((r) => r.shown != null).firstOrNull?.t;

  double _error(_Record r) => (r.shown! - (tEnd - r.t)).abs() / (tEnd - r.t);

  double get firstError => _error(records.firstWhere((r) => r.shown != null));

  /// השגיאה היחסית המרבית של הערך המוצג מ-[from], כל עוד נותרו [minTruth]
  /// שניות לפחות: בזרם בפרצים זמן הסיום מקוונטט למחזורים (עד כ-10 שניות).
  double maxError({required double from, double minTruth = 60}) => records
      .where((r) => r.shown != null && r.t >= from && tEnd - r.t >= minTruth)
      .map(_error)
      .fold(0, math.max);

  double errorAt(double t) =>
      _error(records.lastWhere((r) => r.shown != null && r.t <= t));

  int textIncreases({double until = double.infinity}) {
    var count = 0;
    for (var i = 1; i < texts.length && texts[i].$1 <= until; i++) {
      if (texts[i].$2 > texts[i - 1].$2) count++;
    }
    return count;
  }
}

/// מריץ את המעריך כמו הבלוק: pause לפני ההורדה, קריאה אחרי כל צ'אנק, וטיימר
/// של שנייה. האמת: הזמן עד הצ'אנק האחרון.
_Run _simulate(List<_Chunk> chunks) {
  var ms = 0;
  final total = chunks.fold(0, (sum, c) => sum + c.bytes);
  final estimator = DownloadEtaEstimator(
    clock: () => Duration(milliseconds: ms),
  )..pause();
  final records = <_Record>[];
  final texts = <(double, int)>[];
  String? lastText;
  void observe() {
    final text = estimator.statusText();
    final reading = estimator.lastReading;
    records.add((
      t: ms / 1000,
      shown: reading.remaining == null
          ? null
          : reading.remaining!.inMicroseconds / 1e6,
      status: reading.status,
    ));
    final textRemaining = estimator.textRemaining;
    if (text != lastText && textRemaining != null) {
      texts.add((ms / 1000, roundedRemainingSeconds(textRemaining)));
    }
    lastText = text;
  }

  var bytes = 0;
  var nextTick = 1050;
  for (final chunk in chunks) {
    while (nextTick < chunk.ms) {
      ms = nextTick;
      observe();
      nextTick += 1000;
    }
    ms = chunk.ms;
    bytes += chunk.bytes;
    estimator.addProgress(bytes, total);
    observe();
  }
  return _Run(records, texts, chunks.last.ms / 1000);
}

void main() {
  group('DownloadEtaEstimator — חימום', () {
    test('אין הערכה לפני 3 שניות של נתונים', () {
      final h = _Harness();
      h.report(0);
      h.feed(seconds: 2.5, bytesPerSecond: 10 * _mb);
      expect(h.read().status, EtaStatus.calculating);
      expect(h.read().remaining, isNull);
      expect(h.estimator.statusText(), 'מחשב את הזמן הנותר…');

      h.feed(seconds: 1);
      expect(h.read().status, EtaStatus.estimating);
      expect(h.etaSeconds, closeTo(h.exactEta, h.exactEta * 0.05));
    });

    test('לפני הדיווח הראשון (התחברות): "מחשב", לא זמן שלבי העיבוד בלבד', () {
      final h = _Harness();
      h.estimator.planPhases(const [
        EtaPhase('extract:a', EtaPhaseKind.extract, 400 * _mb),
      ]);
      h.estimator.pause();
      h.advance(const Duration(seconds: 2));
      expect(h.read().status, EtaStatus.calculating);
      expect(h.estimator.statusText(), 'מחשב את הזמן הנותר…');
    });

    test('אין הערכה עד שהגיע מינימום בייטים', () {
      final h = _Harness();
      h.report(0);
      // 100KB/s במשך 5 שניות = 500KB, פחות מ-1MiB ומ-1% מהנותר.
      h.feed(seconds: 5, bytesPerSecond: 100 * 1000);
      expect(h.read().status, EtaStatus.calculating);
    });
  });

  group('DownloadEtaEstimator — בייטים שאינם מהרשת', () {
    test('היסט המשך (resume) אינו נספר כמהירות', () {
      final h = _Harness();
      h.estimator.pause();
      // הדיווח הראשון של קובץ שחודש כולל 600MB שכבר היו על הדיסק.
      h.report(600 * _mb);
      h.feed(seconds: 5, bytesPerSecond: 10 * _mb);
      expect(h.etaSeconds, closeTo(h.exactEta, h.exactEta * 0.05));
    });

    test('קובץ שלם שמדווח (size,size) באמצע אינו זינוק מהירות', () {
      final h = _Harness();
      h.report(0);
      h.feed(seconds: 5, bytesPerSecond: 10 * _mb);
      // דיווח יחיד של 300MB בלי pause — קפיצה גדולה מצ'אנק רשת.
      h.advance(const Duration(milliseconds: 100));
      h.report(h.bytes + 300 * _mb);
      // הזמן יורד מהר (τ=3) עד שולי פס ההיסטרזיס, ולא צונח בגלל "מהירות" מדומה.
      h.feed(seconds: 6);
      expect(h.etaSeconds, closeTo(h.exactEta, h.exactEta * 0.15));
    });

    test('מונה שחוזר אחורה אינו מאפס ואינו מנפח את ההערכה', () {
      final h = _Harness();
      h.report(0);
      h.feed(seconds: 10, bytesPerSecond: 10 * _mb);
      // ניסיון חוזר שאינו ניתן להמשך: ההורדה מתחילה שוב מאפס.
      h.advance(const Duration(milliseconds: 100));
      h.report(1000);
      expect(h.read().status, EtaStatus.estimating);
      h.feed(seconds: 2);
      expect(h.read().status, EtaStatus.estimating);
      // הקצב נשמר, רק הנותר גדל; התצוגה עולה אליו בהדרגה.
      expect(h.etaSeconds, lessThanOrEqualTo(h.exactEta * 1.1));
      expect(h.etaSeconds, greaterThan(50));
    });
  });

  group('DownloadEtaEstimator — שקט', () {
    test('שלב שקט ידוע (pause) אינו הופך להערכה עצומה', () {
      final h = _Harness();
      h.report(0);
      h.feed(seconds: 10, bytesPerSecond: 10 * _mb);
      final before = h.etaSeconds;

      h.estimator.pause();
      // hash של התחילית/חיבור חלקים: דקה בלי דיווחים, בלי מצב תקיעה.
      final ticks = h.silence(60);
      expect(ticks.map((r) => r.status), everyElement(EtaStatus.estimating));
      expect(
        ticks.map((r) => r.remaining!.inMicroseconds / 1e6),
        everyElement(closeTo(before, 1e-6)),
      );
      h.report(h.bytes + 64 * 1024);
      h.feed(seconds: 2);
      // התצוגה קפואה בזמן ההשהיה וממשיכה ממנה, בלי לצנוח ובלי לזנק.
      expect(h.etaSeconds, lessThanOrEqualTo(before));
      expect(h.etaSeconds, closeTo(h.exactEta, h.exactEta * 0.1));
    });

    test('תקיעה מציגה "ממתין לחיבור" במקום הזמן', () {
      final h = _Harness();
      h.report(0);
      h.feed(seconds: 10, bytesPerSecond: 10 * _mb);
      final ticks = h.silence(6);
      expect(ticks[3].status, EtaStatus.estimating);
      expect(ticks[5].status, EtaStatus.stalled);
      expect(ticks[5].remaining, isNull);
      expect(h.estimator.statusText(), 'ממתין לחיבור…');
    });

    test('שתיקות קצרות (<5 שניות) עם תקתוקי טיימר אינן מעלות את הזמן', () {
      final h = _Harness(3000 * _mb);
      h.report(0);
      h.feed(seconds: 20, bytesPerSecond: 10 * _mb);
      var previous = h.etaSeconds;
      for (final gap in [1, 2, 3, 4]) {
        for (final tick in h.silence(gap)) {
          final shown = tick.remaining!.inMicroseconds / 1e6;
          expect(shown, lessThanOrEqualTo(previous));
          previous = shown;
        }
        h.feed(seconds: 5);
        previous = h.etaSeconds;
      }
    });

    test('תקיעה של 12 שניות: אחרי ההתאוששות לא חורג מהאמת+12 ביותר מ-10%', () {
      final h = _Harness(2000 * _mb);
      h.report(0);
      h.feed(seconds: 20, bytesPerSecond: 10 * _mb);
      h.silence(12);
      for (var i = 0; i < 600; i++) {
        h.feed(seconds: 0.1);
        expect(h.etaSeconds, lessThanOrEqualTo((h.exactEta + 12) * 1.1));
      }
    });

    test('תקיעה של 45 שניות: "מחשב" ואז הערכה בטווח 15% מהאמת', () {
      final h = _Harness(2000 * _mb);
      h.report(0);
      h.feed(seconds: 20, bytesPerSecond: 10 * _mb);
      h.silence(45);
      h.feed(seconds: 0.1);
      expect(h.read().status, EtaStatus.calculating);
      expect(h.estimator.statusText(), 'מחשב את הזמן הנותר…');
      while (h.read().status == EtaStatus.calculating) {
        h.feed(seconds: 0.1);
      }
      expect(h.etaSeconds, closeTo(h.exactEta, h.exactEta * 0.15));
    });
  });

  group('DownloadEtaEstimator — שינוי קצב קבוע', () {
    for (final phaseMs in [0, 50, 950]) {
      for (final (from, to) in [(5, 1), (1, 5)]) {
        test('1Hz, טיימר +$phaseMs ms, קצב $from → $to MB/s', () {
          var now = Duration.zero;
          final eta = DownloadEtaEstimator(clock: () => now);
          const total = 2000 * _mb;
          var bytes = 0;
          eta.addProgress(0, total);
          for (var second = 1; second <= 400; second++) {
            now = Duration(seconds: second);
            bytes += (second <= 20 ? from : to) * _mb;
            eta.addProgress(bytes, total);
            eta.read();
            now += Duration(milliseconds: phaseMs);
            final reading = eta.read();
            if (second >= 120) {
              final expected = (total - bytes) / (to * _mb);
              expect(reading.status, EtaStatus.estimating);
              expect(
                reading.remaining!.inMicroseconds / 1e6,
                closeTo(expected, expected * 0.15),
              );
            }
          }
        });
      }
    }

    for (final (from, to) in [(10, 5), (5, 10)]) {
      test('$from → $to MB/s: בטווח 10% מהאמת אחרי 45 שניות', () {
        final h = _Harness(3000 * _mb);
        h.report(0);
        h.feed(seconds: 30, bytesPerSecond: from * _mb);
        h.feed(seconds: 45, bytesPerSecond: to * _mb);
        expect(h.etaSeconds, closeTo(h.exactEta, h.exactEta * 0.1));
      });
    }
  });

  group('TransferRateEstimator — פרצים', () {
    test('0.6 שניות נתונים / 0.4 שקט: הקצב בטווח 5% מהממוצע האמיתי', () {
      final rates = _burstyRates(
        dataSeconds: 0.6,
        silenceSeconds: 0.4,
        avgRate: 5.0 * _mb,
      );
      for (final r in rates) {
        expect(r, closeTo(5 * _mb, 0.05 * 5 * _mb));
      }
    });

    for (final silence in [1.9, 4.9]) {
      test('0.6 שניות נתונים / $silence שקט: בטווח 10%', () {
        final rates = _burstyRates(
          dataSeconds: 0.6,
          silenceSeconds: silence,
          avgRate: 5.0 * _mb,
        );
        for (final r in rates) {
          expect(r, closeTo(5 * _mb, 0.1 * 5 * _mb));
        }
      });
    }
  });

  group('DownloadEtaEstimator — שלבי עיבוד', () {
    test('הזמן הנותר כולל את שלבי העיבוד המתוכננים', () {
      final h = _Harness();
      h.estimator.planPhases(const [
        EtaPhase('extract:a', EtaPhaseKind.extract, 400 * _mb),
      ]);
      h.report(0);
      h.feed(seconds: 10, bytesPerSecond: 10 * _mb);
      // 400MB בברירת המחדל של 40MB/s = 10 שניות נוספות.
      expect(h.etaSeconds, closeTo(h.exactEta + 10, h.exactEta * 0.05));
    });

    test('שלב בלי דיווחים מוצג בשמו ונספר לאחור עד "כמה שניות"', () {
      const join = EtaPhase('join:a', EtaPhaseKind.join, 1000 * _mb);
      final h = _Harness(100 * _mb);
      h.estimator.planPhases(const [join]);
      h.report(0);
      h.feed(seconds: 10, bytesPerSecond: 10 * _mb);
      h.estimator.startPhase(join, tracksProgress: false);
      final first = h.read();
      expect(first.status, EtaStatus.phase);
      expect(first.remaining!.inSeconds, 10);
      expect(h.estimator.statusText(), startsWith('מחבר חלקים…'));

      h.silence(4);
      expect(h.read().remaining!.inSeconds, 6);
      h.silence(20);
      expect(h.read().remaining, Duration.zero);
      h.advance(const Duration(seconds: 2));
      expect(h.estimator.statusText(), 'מחבר חלקים…\nעוד כמה שניות');
    });

    test('שלב עם התקדמות נמדד בקצב החי שלו', () {
      const extract = EtaPhase('extract:a', EtaPhaseKind.extract, 600 * _mb);
      final h = _Harness(10 * _mb);
      h.estimator.planPhases(const [extract]);
      h.report(10 * _mb);
      h.estimator.finishDownload();
      h.estimator.startPhase(extract);
      // 10MB/s בפועל — איטי פי 4 מברירת המחדל של 40MB/s.
      for (var i = 1; i <= 160; i++) {
        h.advance(const Duration(milliseconds: 250));
        h.estimator.phaseProgress((i * 2.5).round() * _mb);
        h.read();
      }
      // 400MB עובדו מתוך 600 => 20 שניות (פס ההיסטרזיס ±5); בברירת המחדל היה 5.
      expect(h.etaSeconds, closeTo(20, 5));
    });
  });

  group('DownloadEtaEstimator — רענון טקסט', () {
    test('טקסט הזמן מתחלף לכל היותר פעם בשנייה', () {
      final h = _Harness(400 * _mb);
      h.report(0);
      h.feed(seconds: 10, bytesPerSecond: 10 * _mb);
      final first = h.estimator.statusText();
      h.feed(seconds: 0.5, bytesPerSecond: 100 * _mb);
      expect(h.estimator.statusText(), first);
      h.feed(seconds: 1, bytesPerSecond: 100 * _mb);
      h.advance(const Duration(milliseconds: 1100));
      expect(h.estimator.statusText(), isNot(first));
    });
  });

  group('EtaCountdownDisplay', () {
    /// זרימה רציפה: עדכון טרי כל 100ms עם [raw] קבוע, מ-[from] עד [to].
    double flow(EtaCountdownDisplay d, double raw, double from, double to) {
      var shown = 0.0;
      for (var t = from; t <= to + 1e-9; t += 0.1) {
        shown = d.update(raw, t, fresh: true);
      }
      return shown;
    }

    test('ספירה לאחור יציבה כשהנתונים מגיעים פעם בשנייה, תחת רעש', () {
      final display = EtaCountdownDisplay();
      display.update(300, 0, fresh: true);
      var previous = 300.0;
      for (var t = 1; t <= 60; t++) {
        final raw = 300.0 - t + (t.isEven ? 12 : -12);
        final shown = display.update(raw, t.toDouble(), fresh: true);
        expect(shown, lessThanOrEqualTo(previous));
        expect(shown, closeTo(300.0 - t, 2));
        previous = shown;
      }
    });

    test('בזרימה רציפה: עלייה איטית, ירידה מהירה', () {
      final same = EtaCountdownDisplay();
      final up = EtaCountdownDisplay();
      final down = EtaCountdownDisplay();
      for (final d in [same, up, down]) {
        flow(d, 100, 0, 3);
      }
      // 2 שניות של זרימה עם גולמי חדש, באותו מרחק למעלה ולמטה.
      final base = flow(same, 100, 3.1, 5);
      final rose = flow(up, 150, 3.1, 5) - base;
      final fell = base - flow(down, 50, 3.1, 5);
      expect(rose, greaterThan(0));
      expect(rose, lessThan(50 * 0.2));
      expect(fell, greaterThan(rose * 2));
    });

    test('ירידה לפחות ממחצית מוצגת בנקודת התיקון הבאה', () {
      final display = EtaCountdownDisplay();
      flow(display, 100, 0, 3);
      expect(display.update(30, 3.1, fresh: true), closeTo(30, 1e-9));
    });

    test('סוף פרץ מתקן לפי הגולמי של הדגימה האחרונה, לא לפי הנוכחי', () {
      final display = EtaCountdownDisplay();
      display.update(100, 0, fresh: true);
      display.update(30, 0.5, fresh: true);
      // פחות משנייה של שקט — עדיין לא סוף פרץ.
      expect(display.update(500, 1, fresh: false), closeTo(99, 1e-9));
      // שנייה של שקט: ירידה לפחות ממחצית — לפי 30 של הדגימה האחרונה.
      expect(display.update(500, 1.5, fresh: false), closeTo(30, 1e-9));
      // אחרי כן שקט: ספירה לאחור בלבד.
      expect(display.update(500, 2.5, fresh: false), closeTo(29, 1e-9));
    });

    test('בלי נקודת תיקון: ספירה לאחור בלבד', () {
      final display = EtaCountdownDisplay()..update(100, 0, fresh: true);
      // פחות משנייה בין דגימות — עוד אין סוף פרץ או שתי שניות של זרימה.
      expect(display.update(200, 0.9, fresh: true), 99.1);
    });
  });

  group("סימולציה מציאותית (צ'אנקים, טיימר של שנייה)", () {
    test('יציב 3GB ב-5MB/s עם רעש ±40%: אין עליות טקסט, שגיאה עד 10%', () {
      final run = _simulate(
        _steady(totalBytes: 3000 * _mb, rate: 5 * _mb, jitter: 0.4),
      );
      expect(run.textIncreases(), 0);
      expect(run.maxError(from: 10), lessThan(0.10));
    });

    test('פרצים 0.6/4.9: עד 15% אחרי חימום+20 שניות', () {
      final run = _simulate(_bursty(offSeconds: [4.9]));
      expect(run.maxError(from: run.firstShownT! + 20), lessThan(0.15));
    });

    test('פרצים 0.6/1.9: עד 10% אחרי חימום+20 שניות', () {
      final run = _simulate(_bursty(offSeconds: [1.9]));
      expect(run.maxError(from: run.firstShownT! + 20), lessThan(0.10));
    });

    test('פרצים 0.6/2.0: הערכה ראשונה עד 20%, לכל היותר 3 עליות טקסט', () {
      final run = _simulate(_bursty(offSeconds: [2.0]));
      expect(run.firstError, lessThan(0.20));
      expect(run.textIncreases(until: 120), lessThanOrEqualTo(3));
    });

    test('פרצים 3/4.9: לכל היותר 3 עליות טקסט ב-120 שניות', () {
      final run = _simulate(_bursty(onChunks: 30, offSeconds: [4.9]));
      expect(run.textIncreases(until: 120), lessThanOrEqualTo(3));
    });

    for (final off in [6.0, 9.0]) {
      test('פרצים 0.6/$off (שקט ארוך שחוזר): עד 15% אחרי 60 שניות', () {
        final run = _simulate(_bursty(offSeconds: [off]));
        expect(run.maxError(from: 60), lessThan(0.15));
      });
    }

    test('שקט שנע סביב 5 שניות (4.8, 5.1, 4.9, 5.3): עד 15% אחרי 60 שניות', () {
      final run = _simulate(_bursty(offSeconds: [4.8, 5.1, 4.9, 5.3]));
      expect(run.maxError(from: 60), lessThan(0.15));
    });

    for (final (from, to) in [(10, 5), (5, 10)]) {
      test('$from → $to MB/s: עד 10% אחרי 45 שניות', () {
        final run = _simulate(
          _segments([(30, from * _mb), (100000, to * _mb)], 3000 * _mb),
        );
        expect(run.errorAt(75), lessThan(0.10));
      });
    }

    test('תקיעה בודדת של 12 שניות: לא חורג מהאמת+12 ביותר מ-10%', () {
      final run = _simulate(
        _segments([(20, 10 * _mb), (12, 0), (100000, 10 * _mb)], 2000 * _mb),
      );
      for (final r in run.records.where((r) => r.t > 32 && r.shown != null)) {
        expect(r.shown!, lessThanOrEqualTo((run.tEnd - r.t + 12) * 1.1));
      }
    });

    test('תקיעה בודדת של 12 שניות אחרי החימום: אין "מחשב" אחרי ההתאוששות', () {
      // 6 שניות של נתונים בלבד: הפער של 12 שניות מעלה את דרישת החימום ל-15.
      final run = _simulate(
        _segments([(6, 10 * _mb), (12, 0), (100000, 10 * _mb)], 2000 * _mb),
      );
      final afterWarmUp = run.records.where((r) => r.t > run.firstShownT!);
      expect(
        afterWarmUp.map((r) => r.status),
        isNot(contains(EtaStatus.calculating)),
      );
      expect(
        afterWarmUp.where((r) => r.t > 11 && r.t < 18).map((r) => r.status),
        contains(EtaStatus.stalled),
      );
    });

    test('תקיעה של 45 שניות: "מחשב" ואז עד 15% מהאמת', () {
      final run = _simulate(
        _segments([(20, 10 * _mb), (45, 0), (100000, 10 * _mb)], 2000 * _mb),
      );
      final after = run.records.where((r) => r.t > 65.05).toList();
      expect(after.first.status, EtaStatus.calculating);
      final reappeared = after.firstWhere((r) => r.shown != null);
      expect(
        (reappeared.shown! - (run.tEnd - reappeared.t)).abs() /
            (run.tEnd - reappeared.t),
        lessThan(0.15),
      );
    });
  });

  group('formatRemainingTimeHebrew', () {
    String f(num seconds) => formatRemainingTimeHebrew(
      Duration(milliseconds: (seconds * 1000).round()),
    );

    test('טבלת הדליים', () {
      expect(f(0), 'עוד כמה שניות');
      expect(f(4.7), 'עוד כמה שניות');
      expect(f(4.9), 'עוד כמה שניות');
      expect(f(5), 'נותרו כ-5 שניות');
      expect(f(44), 'נותרו כ-45 שניות');
      expect(f(59), 'נותרה כדקה');
      expect(f(60), 'נותרה כדקה');
      expect(f(90), 'נותרו כדקה ו-30 שניות');
      expect(f(200), 'נותרו כ-3 דקות ו-20 שניות');
      expect(f(300), 'נותרו כ-5 דקות');
      expect(f(599), 'נותרו כ-10 דקות');
      expect(f(600), 'נותרו כ-10 דקות');
      expect(f(1830), 'נותרו כ-31 דקות');
      expect(f(3599), 'נותרה כשעה');
      expect(f(3600), 'נותרה כשעה');
      expect(f(4500), 'נותרו כשעה ו-15 דקות');
      expect(f(7200), 'נותרו כשעתיים');
      expect(f(7500), 'נותרו כשעתיים ו-5 דקות');
      expect(f(3 * 3600 + 20 * 60), 'נותרו כ-3 שעות ו-20 דקות');
    });
  });
}
