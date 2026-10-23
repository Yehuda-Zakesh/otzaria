import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_process_recovery.dart';

void main() {
  late DateTime now;
  PluginProcessRecovery recovery() => PluginProcessRecovery(clock: () => now);

  setUp(() => now = DateTime(2026, 10, 21, 12));

  test('שתי התאוששויות בחלון, ואז ויתור', () {
    final r = recovery();
    expect(r.consume(), isTrue);
    expect(r.consume(), isTrue);
    expect(r.consume(), isFalse);
  });

  test('חלון שפג מחזיר את התקציב', () {
    final r = recovery();
    r
      ..consume()
      ..consume();
    expect(r.consume(), isFalse);
    now = now.add(const Duration(minutes: 2));
    expect(r.consume(), isTrue);
  });

  test('reset של המשתמש מחזיר את התקציב מיד', () {
    final r = recovery();
    r
      ..consume()
      ..consume();
    expect(r.consume(), isFalse);
    r.reset();
    expect(r.consume(), isTrue);
  });
}
