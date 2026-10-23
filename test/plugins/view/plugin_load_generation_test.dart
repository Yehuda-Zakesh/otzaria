import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_load_generation.dart';

void main() {
  test('טעינה חדשה מבטלת זרימה שעדיין ממתינה', () {
    final generations = PluginLoadGeneration();
    final first = generations.begin();
    expect(generations.isCurrent(first), isTrue);

    // reload בזמן ההמתנה לגופנים: onLoadStart ואחריו onLoadStop של הדף החדש.
    generations.invalidate();
    expect(generations.isCurrent(first), isFalse);
    final second = generations.begin();
    expect(generations.isCurrent(first), isFalse);
    expect(generations.isCurrent(second), isTrue);
  });

  test('onLoadStop נוסף בלי onLoadStart גם הוא מחליף את הזרימה', () {
    final generations = PluginLoadGeneration();
    final first = generations.begin();
    final second = generations.begin();
    expect(generations.isCurrent(first), isFalse);
    expect(generations.isCurrent(second), isTrue);
  });
}
