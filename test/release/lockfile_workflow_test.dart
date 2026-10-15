import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  final release = loadYaml(
    File('.github/workflows/build-and-announce.yml').readAsStringSync(),
  );
  final guard = loadYaml(
    File('.github/workflows/lockfile_guard.yml').readAsStringSync(),
  );
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('otzaria_lockfile_'));
  tearDown(() => temp.deleteSync(recursive: true));

  bool available(String executable) {
    try {
      return Process.runSync(executable, ['--version']).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  for (final job in ['build_windows', 'build_windows_arm64']) {
    for (final code in [0, 65]) {
      test('$job: אכיפת נעילה מחזירה $code לפני המחוללים', () async {
        if (!available('pwsh')) {
          markTestSkipped('PowerShell is unavailable');
          return;
        }
        final bin = Directory(p.join(temp.path, 'bin'))..createSync();
        final marker = File(p.join(temp.path, 'generators'));
        for (final command in ['git', 'flutter', 'dart']) {
          final exit = command == 'flutter' ? code : 0;
          final file = File(
            p.join(bin.path, '$command${Platform.isWindows ? '.cmd' : ''}'),
          );
          file.writeAsStringSync(
            Platform.isWindows
                ? '@echo off\r\n'
                      '${command == 'dart' ? 'echo called>>"%REVIEW_MARKER%"\r\n' : ''}'
                      'exit /b $exit\r\n'
                : '#!/bin/sh\n'
                      '${command == 'dart' ? 'echo called >> "\$REVIEW_MARKER"\n' : ''}'
                      'exit $exit\n',
          );
          if (!Platform.isWindows) {
            expect((await Process.run('chmod', ['+x', file.path])).exitCode, 0);
          }
        }
        final steps = release['jobs'][job]['steps'] as YamlList;
        final body = steps.cast<YamlMap>().firstWhere(
          (step) =>
              step['name'] ==
              'Prepare Flutter dependencies for Windows release',
        )['run'];
        final script = File(p.join(temp.path, 'run.ps1'))
          ..writeAsStringSync(
            "\$ErrorActionPreference = 'stop'\n"
            '$body\n'
            r'if (Test-Path -LiteralPath variable:\LASTEXITCODE) { exit $LASTEXITCODE }',
          );
        final result = await Process.run(
          'pwsh',
          ['-NoProfile', '-File', script.path],
          environment: {
            'PATH':
                '${bin.path}${Platform.isWindows ? ';' : ':'}'
                '${Platform.environment['PATH']}',
            'REVIEW_MARKER': marker.path,
          },
        );
        expect(
          result.exitCode,
          code,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(marker.existsSync(), code == 0);
        if (code == 0) expect(marker.readAsLinesSync(), hasLength(2));
      });
    }
  }

  group(
    'Lockfile Guard',
    () {
      Future<ProcessResult> runGuard(
        List<Map<String, String>> files, {
        bool label = false,
      }) async {
        final fixture = File(p.join(temp.path, 'files.json'))
          ..writeAsStringSync(jsonEncode(files));
        final bin = Directory(p.join(temp.path, 'bin'))..createSync();
        final gh = File(p.join(bin.path, 'gh'))
          ..writeAsStringSync('''#!/bin/sh
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "--jq" ]; then
    exec jq -r "\$2" "\$REVIEW_FILES"
  fi
  shift
done
exit 1
''');
        expect((await Process.run('chmod', ['+x', gh.path])).exitCode, 0);
        final script =
            File(
              p.join(temp.path, 'guard.sh'),
            )..writeAsStringSync(
              guard['jobs']['guard']['steps'][0]['run'] as String,
            );
        return Process.run(
          'bash',
          [script.path],
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'REVIEW_FILES': fixture.path,
            'REPO': 'Otzaria/otzaria',
            'PR_NUMBER': '1',
            'BASE_REF': 'dev',
            'DEPENDENCIES_LABEL': '$label',
          },
        );
      }

      for (final status in ['modified', 'removed', 'added']) {
        test('$status ללא שינוי YAML או תווית', () async {
          final result = await runGuard([
            {'status': status, 'filename': 'pubspec.lock'},
          ]);
          expect(result.exitCode, status == 'added' ? 0 : 1);
        });
      }
      test('ללא שינוי בנעילה', () async {
        expect((await runGuard([])).exitCode, 0);
      });
      test('שינוי תלויות מכוון עם YAML או תווית', () async {
        const lock = {'status': 'modified', 'filename': 'pubspec.lock'};
        expect((await runGuard([lock], label: true)).exitCode, 0);
        expect(
          (await runGuard([
            lock,
            {'status': 'modified', 'filename': 'pubspec.yaml'},
          ])).exitCode,
          0,
        );
      });
      test('שינוי שם אמיתי של הנעילה עדיין מחייב שינוי מכוון', () async {
        Future<ProcessResult> git(List<String> args) =>
            Process.run('git', args, workingDirectory: temp.path);
        expect((await git(['init', '-q'])).exitCode, 0);
        File(
          p.join(temp.path, 'pubspec.lock'),
        ).writeAsStringSync('packages: {}\n');
        expect((await git(['add', '.'])).exitCode, 0);
        expect(
          (await git([
            '-c',
            'user.name=Review',
            '-c',
            'user.email=review@example.invalid',
            'commit',
            '-qm',
            'fixture',
          ])).exitCode,
          0,
        );
        expect((await git(['mv', 'pubspec.lock', 'backup.lock'])).exitCode, 0);
        final diff = await git(['diff', '--cached', '--name-status', '-M']);
        final names = (diff.stdout as String).trim().split('\t');
        expect(names[0], 'R100');
        final result = await runGuard([
          {
            'status': 'renamed',
            'filename': names[2],
            'previous_filename': names[1],
          },
        ]);
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
      });
    },
    skip: Platform.isWindows
        ? 'The guard runs on Linux'
        : !available('jq') || !available('bash')
        ? 'The guard requires bash and jq'
        : false,
  );
}
