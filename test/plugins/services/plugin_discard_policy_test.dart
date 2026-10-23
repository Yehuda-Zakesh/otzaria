import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';

PluginInstanceKey _k(String id) => (pluginId: 'p', instanceId: id);

final _t0 = DateTime(2026, 10, 21, 12);

PluginDiscardCandidate _c(String id, int minutesAgo, {bool exempt = false}) =>
    PluginDiscardCandidate(
      key: _k(id),
      suspendedAt: _t0.subtract(Duration(minutes: minutesAgo)),
      exempt: exempt,
    );

const _limits = PluginDiscardLimits(
  maxLiveSuspended: 2,
  maxSuspendedAge: Duration(minutes: 30),
);

void main() {
  test('בתוך התקרה ובתוך הגיל — אין פינוי', () {
    expect(
      pickDiscardVictims([_c('a', 1), _c('b', 5)], now: _t0, limits: _limits),
      isEmpty,
    );
  });

  test('מעבר לתקרה — הוותיק ביותר מפונה', () {
    expect(
      pickDiscardVictims(
        [_c('new', 1), _c('old', 10), _c('mid', 5)],
        now: _t0,
        limits: _limits,
      ),
      [_k('old')],
    );
  });

  test('מושהה יותר מהגיל המרבי — מפונה גם בתוך התקרה', () {
    expect(
      pickDiscardVictims([_c('a', 31), _c('b', 1)], now: _t0, limits: _limits),
      [_k('a')],
    );
  });

  test('מוחרג אינו מפונה, אבל נספר בתקרה', () {
    expect(
      pickDiscardVictims(
        [_c('x', 50, exempt: true), _c('y', 20, exempt: true), _c('z', 1)],
        now: _t0,
        limits: _limits,
      ),
      [_k('z')],
    );
  });

  test('לחץ זיכרון — כל מי שמותר, מהוותיק', () {
    expect(
      pickDiscardVictims(
        [_c('a', 1), _c('b', 2, exempt: true), _c('c', 3)],
        now: _t0,
        limits: _limits,
        memoryPressure: true,
      ),
      [_k('c'), _k('a')],
    );
  });

  test('ישן וגם מעבר לתקרה — לא נספר פעמיים', () {
    expect(
      pickDiscardVictims(
        [_c('a', 40), _c('b', 3), _c('c', 2), _c('d', 1)],
        now: _t0,
        limits: _limits,
      ),
      [_k('a'), _k('b')],
    );
  });

  test('מגבלות לפי פלטפורמה', () {
    final windows = PluginDiscardLimits.forPlatform(TargetPlatform.windows);
    expect(windows.maxLiveSuspended, 6);
    expect(windows.maxSuspendedAge, const Duration(minutes: 60));
    final android = PluginDiscardLimits.forPlatform(TargetPlatform.android);
    expect(android.maxLiveSuspended, 2);
    expect(android.maxSuspendedAge, const Duration(minutes: 15));
    final mac = PluginDiscardLimits.forPlatform(TargetPlatform.macOS);
    expect(mac.maxLiveSuspended, 3);
    expect(mac.maxSuspendedAge, const Duration(minutes: 30));
  });
}
