import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  final workflow =
      loadYaml(
            File(
              '.github/workflows/library_index_schema_trigger.yml',
            ).readAsStringSync(),
          )
          as YamlMap;
  final steps = workflow['jobs']['check']['steps'] as YamlList;
  final body = (steps.last as YamlMap)['run'] as String;
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('otzaria_schema_trigger_');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<List<dynamic>> runTrigger({
    int stored = 5,
    int current = 6,
    int previous = 5,
    bool provenance = true,
    String status = 'in_progress',
    String event = 'push',
  }) async {
    final bin = Directory(p.join(temp.path, 'bin'))..createSync();
    String lock(int schema) {
      final engine = Directory(p.join(temp.path, 'engine$schema'));
      File(p.join(engine.path, 'rust/src/api/search_engine.rs'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'const INDEX_FORMAT: &str = "otzaria-search-index";\n'
          'pub(crate) const INDEX_SCHEMA_VERSION: u32 = $schema;\n',
        );
      return '''
packages:
  otzaria_search_engine:
    description:
      path: "${engine.path}"
      relative: false
    source: path
    version: "4.0.0"
''';
    }

    File(p.join(temp.path, 'pubspec.lock')).writeAsStringSync(lock(current));
    File(p.join(temp.path, 'stored.lock')).writeAsStringSync(lock(stored));
    File(p.join(temp.path, 'previous.lock')).writeAsStringSync(lock(previous));
    File(p.join(temp.path, 'release.json')).writeAsStringSync(
      jsonEncode({
        'tag_name': 'v32-20261010190601',
        'assets': [
          if (provenance) {'name': 'otzaria-library-index.provenance.json'},
        ],
      }),
    );
    File(p.join(temp.path, 'runs.json')).writeAsStringSync(
      jsonEncode([
        {
          'status': status,
          'displayTitle': 'library-index v32-20261010190601',
          'url': 'https://example.invalid/build',
        },
      ]),
    );
    final helper = File(
      p.join(temp.path, 'tool/release/engine_index_schema.sh'),
    )..createSync(recursive: true);
    File('tool/release/engine_index_schema.sh').copySync(helper.path);
    File(p.join(temp.path, 'trigger.sh')).writeAsStringSync(body);
    final stubs = {
      'gh': r'''#!/bin/bash
set -eu
case "$*" in
  'api repos/Otzaria/SeforimLibrary/releases/latest') cat release.json ;;
  *'contents/pubspec.lock?ref=stored'*) cat stored.lock ;;
  *'contents/pubspec.lock?ref=previous'*) cat previous.lock ;;
  'run list '*)
    while [ "$1" != --jq ]; do shift; done
    jq -r "$2" runs.json ;;
  *) echo "Unexpected gh request: $*" >&2; exit 1 ;;
esac
''',
      'curl': r'''#!/bin/bash
set -eu
case "$*" in
  *' -X POST '*) cat > dispatch.json ;;
  *'otzaria-library-index.provenance.json'*)
    while [ "$1" != -o ]; do shift; done
    printf '{"otzaria":{"sha":"stored"}}' > "$2" ;;
  *) echo "Unexpected curl request: $*" >&2; exit 1 ;;
esac
''',
    };
    for (final entry in stubs.entries) {
      final file = File(p.join(bin.path, entry.key))
        ..writeAsStringSync(entry.value);
      expect((await Process.run('chmod', ['+x', file.path])).exitCode, 0);
    }
    final result = await Process.run(
      'bash',
      ['trigger.sh'],
      workingDirectory: temp.path,
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'RUNNER_TEMP': temp.path,
        'GITHUB_REPOSITORY': 'Otzaria/otzaria',
        'GITHUB_REF_NAME': 'dev',
        'GITHUB_SHA': 'current',
        'GITHUB_EVENT_NAME': event,
        'BEFORE_SHA': event == 'push' ? 'previous' : '',
        'SEFORIM_LIBRARY_DISPATCH_TOKEN': 'fixture-token',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final dispatched = File(p.join(temp.path, 'dispatch.json'));
    return dispatched.existsSync()
        ? [jsonDecode(dispatched.readAsStringSync())]
        : [];
  }

  group('הפעלת בלוק ה-workflow עם gh ו-curl מדומים', () {
    for (final status in ['queued', 'in_progress', 'completed']) {
      test('מעבר 5 ל-6 אינו אובד כאשר ריצת סכמה 5 היא $status', () async {
        expect(await runTrigger(status: status), [
          {
            'ref': 'otzaria',
            'inputs': {
              'release_tag': 'v32-20261010190601',
              'otzaria_ref': 'dev',
            },
          },
        ]);
      });
    }
    test(
      'עדכון lock נוסף בסכמה 6 אינו מוסיף בנייה בזמן שסכמה 6 ממתינה',
      () async {
        expect(await runTrigger(previous: 6, status: 'queued'), isEmpty);
      },
    );
    test('עדכון lock רגיל אינו משגר שוב גם אם אין בנייה פעילה', () async {
      expect(await runTrigger(previous: 6, status: 'completed'), isEmpty);
    });
    test('עדכון lock רגיל ללא provenance אינו משגר בנייה', () async {
      expect(await runTrigger(previous: 6, provenance: false), isEmpty);
    });
    test('אינדקס שהושלם בסכמה 6 אינו נבנה מחדש', () async {
      expect(
        await runTrigger(stored: 6, previous: 6, status: 'completed'),
        isEmpty,
      );
    });
    test('חזרה ל-5 נשמרת גם אם אינדקס 5 שמור ובניית 6 עדיין בתור', () async {
      expect(
        await runTrigger(stored: 5, current: 5, previous: 6, status: 'queued'),
        hasLength(1),
      );
    });
    test('ללא provenance מעבר הסכמה עדיין משוגר', () async {
      expect(await runTrigger(provenance: false), hasLength(1));
    });
    test('הפעלה ידנית מאפשרת ניסיון חוזר ללא מעבר סכמה', () async {
      expect(
        await runTrigger(previous: 6, event: 'workflow_dispatch'),
        hasLength(1),
      );
    });
    test('הפעלה ידנית ללא provenance אינה מניחה שיש בנייה בתור', () async {
      expect(
        await runTrigger(provenance: false, event: 'workflow_dispatch'),
        hasLength(1),
      );
    });
  }, skip: Platform.isWindows ? 'The workflow runs on Linux' : false);

  test('מעברי סכמה ממתינים אינם מוחלפים בעדכוני lock מאוחרים', () {
    expect(workflow['concurrency']['cancel-in-progress'], false);
    expect(workflow['concurrency']['queue'], 'max');
    expect(
      (steps.last as YamlMap)['env']['BEFORE_SHA'],
      r'${{ github.event.before }}',
    );
  });
}
