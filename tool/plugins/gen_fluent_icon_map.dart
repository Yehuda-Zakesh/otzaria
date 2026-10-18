// ignore_for_file: avoid_print
//
// מפת שמות Fluent לתוספים, עם מפתח בסיס משותף למשקלים.
// הרצה: dart run tool/plugins/gen_fluent_icon_map.dart [--check]

import 'dart:convert';
import 'dart:io';

const String outputPath = 'lib/plugins/utils/fluent_icon_resolver.dart';

final RegExp _iconLine = RegExp(
  r"static const IconData ([a-z0-9_]+_24_(?:regular|filled|light)) = "
  r"IconData\((\d+), fontFamily: '([A-Za-z-]+)', fontPackage: _kFontPkg"
  r"(, matchTextDirection: true)?\);",
);

class _FluentIcon {
  final int codePoint;
  final String fontFamily;
  final bool matchTextDirection;
  const _FluentIcon(this.codePoint, this.fontFamily, this.matchTextDirection);
}

void main(List<String> args) {
  final root = Directory.current;
  final output = buildFluentIconMap(root);
  final file = File('${root.path}/$outputPath');
  final current = file.existsSync()
      ? file.readAsStringSync().replaceAll('\r\n', '\n')
      : '';
  if (current == output) {
    print('$outputPath מעודכן.');
    return;
  }
  if (args.contains('--check')) {
    stderr.writeln(
      '$outputPath אינו תואם לספריית פלואנט. הרץ: '
      'dart run tool/plugins/gen_fluent_icon_map.dart',
    );
    exit(1);
  }
  file.writeAsStringSync(output);
  print('נכתב $outputPath.');
}

/// בונה את מפת כל שמות פלואנט הנתמכים מתוך החבילה הנעוצה.
String buildFluentIconMap(Directory root) {
  final packageRoot = _packageRoot(root, 'fluentui_system_icons');
  final icons = _parseIcons(
    File('$packageRoot/lib/src/fluent_icons.dart').readAsStringSync(),
  )..removeWhere((_, icon) => icon.matchTextDirection);
  return _render(_packageVersion(packageRoot), icons);
}

Map<String, _FluentIcon> _parseIcons(String source) => {
  for (final m in _iconLine.allMatches(source))
    m.group(1)!: _FluentIcon(
      int.parse(m.group(2)!),
      m.group(3)!,
      m.group(4) != null,
    ),
};

String _render(String version, Map<String, _FluentIcon> icons) {
  final variants = <String, Map<String, _FluentIcon>>{};
  for (final entry in icons.entries) {
    final separator = entry.key.lastIndexOf('_24_');
    variants.putIfAbsent(
      entry.key.substring(0, separator),
      () => {},
    )[entry.key.substring(separator + 4)] = entry.value;
  }
  final bases = variants.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('// GENERATED — do not edit manually.')
    ..writeln('// Source: fluentui_system_icons $version (24px variants only).')
    ..writeln(
      '// Regenerate with: dart run tool/plugins/gen_fluent_icon_map.dart',
    )
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln()
    ..writeln("const _kFontPkg = 'fluentui_system_icons';")
    ..writeln()
    ..writeln(
      '/// ממיר שם אייקון FluentUI בגודל 24 ל-IconData; שם לא מוכר מחזיר null.',
    )
    ..writeln('IconData? fluentIconFromName(String? name) {')
    ..writeln('  if (name == null) return null;');
  for (final (index, weight) in ['regular', 'filled', 'light'].indexed) {
    final suffix = '_24_$weight';
    buffer
      ..writeln("  if (name.endsWith('$suffix')) {")
      ..writeln(
        '    return _iconMap[name.substring(0, name.length - ${suffix.length})]?.\$${index + 1};',
      )
      ..writeln('  }');
  }
  buffer
    ..writeln('  return null;')
    ..writeln('}')
    ..writeln()
    ..writeln('const _iconMap = <String, (IconData?, IconData?, IconData?)>{');
  for (final base in bases) {
    buffer.writeln("  '$base': (");
    for (final weight in ['regular', 'filled', 'light']) {
      final icon = variants[base]![weight];
      if (icon == null) {
        buffer.writeln('    null,');
      } else {
        buffer
          ..writeln('    IconData(')
          ..writeln('      ${icon.codePoint},')
          ..writeln("      fontFamily: '${icon.fontFamily}',")
          ..writeln('      fontPackage: _kFontPkg,')
          ..writeln('    ),');
      }
    }
    buffer.writeln('  ),');
  }
  buffer.writeln('};');
  return buffer.toString();
}

String _packageRoot(Directory root, String package) {
  final config =
      jsonDecode(
            File(
              '${root.path}/.dart_tool/package_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final entry in config['packages'] as List<dynamic>) {
    final map = entry as Map<String, dynamic>;
    if (map['name'] == package) {
      final base = Uri.directory('${root.absolute.path}/.dart_tool/');
      return Directory.fromUri(
        base.resolve(map['rootUri'] as String),
      ).path.replaceAll(RegExp(r'[\\/]$'), '');
    }
  }
  throw StateError(
    '$package לא נמצא ב-package_config.json — הרץ flutter pub get',
  );
}

String _packageVersion(String root) {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('$root/pubspec.yaml').readAsStringSync());
  return match?.group(1) ?? 'unknown';
}
