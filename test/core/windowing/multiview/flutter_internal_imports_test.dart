import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ה-API הפנימי של Flutter משתנה גם בגרסאות תיקון; כשהוא נשבר צריך לדעת
/// מראש שיש רק קובץ אחד לתקן.
void main() {
  test('package:flutter/src/ מיובא רק ב-multiview_flag.dart', () {
    final importers = <String>{
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            file.readAsLinesSync().any(
              (line) => RegExp(
                r'''^\s*(import|export)\s+['"]package:flutter/src/''',
              ).hasMatch(line),
            ))
          file.path.replaceAll(r'\', '/'),
    };
    expect(importers, {
      'lib/core/windowing/multiview/multiview_flag.dart',
    }, reason: 'כל שימוש ב-API הפנימי עובר דרך multiview_flag.dart');
  });
}
