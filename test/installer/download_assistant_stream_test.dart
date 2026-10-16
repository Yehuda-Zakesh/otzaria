import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _routine(String script, String name) {
  final start = script.indexOf('function $name(');
  final next = RegExp(
    r'^(?:function|procedure) ',
    multiLine: true,
  ).firstMatch(script.substring(start + 1));
  return script.substring(start, start + 1 + next!.start);
}

void main() {
  String? compiler;
  try {
    if (Process.runSync('fpc', ['-iV']).exitCode == 0) compiler = 'fpc';
  } on ProcessException {
    // בדיקת השגרה המחולצת זמינה כשמותקן Free Pascal.
  }
  final skip = compiler == null ? 'נדרש Free Pascal לבדיקת הזרימה' : false;
  late Directory work;
  late String executable;

  setUpAll(() async {
    if (compiler == null) return;
    work = await Directory.systemTemp.createTemp('assistant-stream-');
    executable = p.join(work.path, 'probe${Platform.isWindows ? '.exe' : ''}');
    final script = File('installer/download_assistant.iss').readAsStringSync();
    final template = File(
      'test/installer/support/download_assistant_stream_probe.pas',
    ).readAsStringSync();
    final source = template.replaceFirst(
      '{EXTRACTED_ROUTINES}',
      ['WriteFileTo', 'CopyToOutput']
          .map((name) => _routine(script, name))
          .join('\n')
          .replaceAll('TFileStream', 'TProbeFileStream'),
    );
    final input = File(p.join(work.path, 'probe.pas'));
    await input.writeAsString(source);
    final result = await Process.run(compiler!, [
      '-o$executable',
      input.path,
    ], workingDirectory: work.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  tearDownAll(() async {
    if (compiler != null) await work.delete(recursive: true);
  });

  for (final scenario in {
    'replace': 'כישלון מחיקה וקישור מחליף יעד קיים ושומר את מטמון המקור',
    'append': 'הוספת חלקים שומרת קידומת ומשלימה את יתרת ההרכבה',
    'copy-before-join': 'העתקה אינה מקטינה את יתרת ההרכבה הממתינה',
    'progress': 'העתקה מדווחת בתים באמצע קובץ בלי ETA של הרכבה',
    'short-input': 'מקור קטוע אינו מאושר כהעתקה שהושלמה',
    'write-failure': 'כישלון כתיבה באמצע אינו מאושר כהצלחה',
    'shared-source': 'פתיחת היעד מכבדת מקור מוגן מכתיבה (הדמיית שיתוף Windows)',
    'source-open-failure': 'מקור שאינו זמין אינו מוחק יעד קיים',
    'unwritable': 'יעד שאינו ניתן לפתיחה אינו מאושר כהצלחה',
    'cache': 'יעד שהוא תיקיית המטמון אינו נכתב מחדש',
    'hardlink': 'קישור מוצלח אינו מפעיל העתקה או משנה יתרת הרכבה',
  }.entries) {
    test(scenario.value, () async {
      final result = await Process.run(executable, [
        scenario.key,
        work.path,
      ], workingDirectory: work.path);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }, skip: skip);
  }
}
