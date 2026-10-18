import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';

Map<String, (int, String)> _expectedIcons() {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final package = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere(
        (entry) => entry['name'] == 'fluentui_system_icons',
      );
  final packageRoot = Directory.fromUri(
    configFile.uri.resolve(package['rootUri'] as String),
  );
  final source = File(
    '${packageRoot.path}/lib/src/fluent_icons.dart',
  ).readAsStringSync();
  final definitions = RegExp(
    r'static const IconData ([a-z0-9_]+) = IconData\((\d+), ([^;]+)\);',
  ).allMatches(source);
  final result = <String, (int, String)>{};
  for (final definition in definitions) {
    final name = definition[1]!;
    final options = definition[3]!;
    if (!RegExp(r'_24_(regular|filled|light)$').hasMatch(name) ||
        options.contains('matchTextDirection: true')) {
      continue;
    }
    final family = RegExp("fontFamily: '([^']+)'").firstMatch(options)![1]!;
    result[name] = (int.parse(definition[2]!), family);
  }
  return result;
}

void main() {
  final expected = _expectedIcons();

  test('כל 4534 השמות הציבוריים נשמרים עם אותו גליף ותחילית Fluent', () {
    expect(expected, hasLength(4534));
    for (final entry in expected.entries) {
      final icon = fluentIconFromName(entry.key);
      expect(icon, isNotNull, reason: entry.key);
      expect(
        (
          icon!.codePoint,
          icon.fontFamily,
          icon.fontPackage,
          icon.matchTextDirection,
          icon.fontFamilyFallback,
        ),
        (entry.value.$1, entry.value.$2, 'fluentui_system_icons', false, null),
        reason: entry.key,
      );
      expect(
        pluginIconFromName('fluent:${entry.key}'),
        icon,
        reason: entry.key,
      );
      final otzaria = pluginIconFromName('otzaria:${entry.key}');
      expect(
        pluginIconFromName(entry.key),
        otzaria ?? icon,
        reason: entry.key,
      );
    }
  });

  test('משקל חסר אינו מקבל גליף ממשקל אחר', () {
    final bases = expected.keys
        .map((name) => name.substring(0, name.lastIndexOf('_24_')))
        .toSet();
    for (final base in bases) {
      for (final weight in ['regular', 'filled', 'light']) {
        final name = '${base}_24_$weight';
        if (expected.containsKey(name)) continue;
        expect(fluentIconFromName(name), isNull, reason: name);
        expect(pluginIconFromName('fluent:$name'), isNull, reason: name);
      }
    }
  });

  test('קלט חסר, שמות שגויים ואייקונים כיווניים נשארים ללא גליף', () {
    expect(fluentIconFromName(null), isNull);
    expect(pluginIconFromName(null), isNull);
    for (final name in [
      '',
      '_24_regular',
      'airplane',
      'AIRPLANE_24_REGULAR',
      'airplane_20_regular',
      'airplane_24_regular_24_regular',
      'airplane_24_regular ',
      ' airplane_24_regular',
      'unknown_24_regular',
      'chevron_left_24_regular',
      'fluent:airplane_24_regular',
    ]) {
      expect(fluentIconFromName(name), isNull, reason: name);
      expect(pluginIconFromName('fluent:$name'), isNull, reason: name);
    }
  });
}
