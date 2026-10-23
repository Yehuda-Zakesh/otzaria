import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/services/release_index_builder_cli.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class _Engine extends Fake implements SearchEngine {
  final modes = <bool>[];
  final events = <String>[];
  Object? optimizeError;

  @override
  Future<void> setBulkIndexing({required bool enabled}) async {
    modes.add(enabled);
    events.add('bulk:$enabled');
  }

  @override
  Future<void> optimize() async {
    events.add('optimize');
    if (optimizeError case final error?) throw error;
  }
}

class _Sink implements StringSink {
  final buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  String toString() => buffer.toString();
}

void main() {
  late _Sink out;
  late _Sink err;

  setUp(() {
    out = _Sink();
    err = _Sink();
  });

  test('מצב bulk פעיל בזמן הבנייה ומשוחזר אחרי הצלחה', () async {
    final engine = _Engine();
    final result = await ReleaseIndexBuilderCli.withBulkIndexing(
      engine,
      () async {
        expect(engine.modes, [true]);
        engine.events.add('build');
        return 42;
      },
    );
    expect(result, 42);
    expect(engine.modes, [true, false]);
    expect(engine.events, ['bulk:true', 'build', 'optimize', 'bulk:false']);
  });

  test('מצב bulk משוחזר גם כשהבנייה נכשלת', () async {
    final engine = _Engine();
    final error = StateError('build failed');
    await expectLater(
      ReleaseIndexBuilderCli.withBulkIndexing(engine, () async => throw error),
      throwsA(same(error)),
    );
    expect(engine.modes, [true, false]);
  });

  test('כשל איחוד אינו מדווח כבניית הפצה מוצלחת ומשחזר מצב רגיל', () async {
    final engine = _Engine()..optimizeError = StateError('optimize failed');
    final code = await ReleaseIndexBuilderCli.run(
      const ['--library=books', '--index=index', '--data=data'],
      out: out,
      err: err,
      build: (_, _) =>
          ReleaseIndexBuilderCli.withBulkIndexing(engine, () async {}),
    );
    expect(code, ReleaseIndexBuilderCliExitCode.buildFailed);
    expect(err.toString(), contains('optimize failed'));
    expect(out.toString(), isNot(contains('נבנה בהצלחה')));
    expect(engine.events, ['bulk:true', 'optimize', 'bulk:false']);
  });

  test('מעביר לבונה את שלושת הנתיבים כנתיבים מוחלטים', () async {
    ReleaseIndexBuilderConfig? received;

    final code = await ReleaseIndexBuilderCli.run(
      const [
        '--library',
        'staging/books',
        '--index=staging/index',
        '--data',
        'staging/data',
      ],
      out: out,
      err: err,
      build: (config, log) async => received = config,
    );

    expect(code, ReleaseIndexBuilderCliExitCode.success);
    expect(received, isNotNull);
    expect(received!.libraryPath, p.absolute('staging/books'));
    expect(received!.indexPath, p.absolute('staging/index'));
    expect(received!.dataPath, p.absolute('staging/data'));
    expect(err.toString(), isEmpty);
  });

  test('מחזיר usage error כשנתיב חובה חסר', () async {
    final code = await ReleaseIndexBuilderCli.run(
      const ['--library', 'books', '--index', 'index'],
      out: out,
      err: err,
      build: (_, _) async => fail('אסור להפעיל את הבונה'),
    );

    expect(code, ReleaseIndexBuilderCliExitCode.usageError);
    expect(err.toString(), contains('--library, --index'));
  });

  test('--help אינו מפעיל בנייה', () async {
    final code = await ReleaseIndexBuilderCli.run(
      const ['--help'],
      out: out,
      err: err,
      build: (_, _) async => fail('אסור להפעיל את הבונה'),
    );

    expect(code, ReleaseIndexBuilderCliExitCode.success);
    expect(out.toString(), contains('build-release-index'));
    expect(err.toString(), isEmpty);
  });

  test('כשל בנייה מוחזר כקוד 1 ונכתב ל-stderr', () async {
    final code = await ReleaseIndexBuilderCli.run(
      const [
        '--library=books',
        '--index=index',
        '--data=data',
      ],
      out: out,
      err: err,
      build: (_, _) async => throw const FileSystemException('boom'),
    );

    expect(code, ReleaseIndexBuilderCliExitCode.buildFailed);
    expect(err.toString(), contains('boom'));
  });

  test('אינדקס להפצה חייב לכלול את מספרי הספרים ואת מיפוי הסדר', () async {
    final dir = await Directory.systemTemp.createTemp('release_order');
    addTearDown(() => dir.delete(recursive: true));
    File(p.join(dir.path, 'otzaria_book_numbers.json')).writeAsStringSync('{}');

    expect(
      () => ReleaseIndexBuilderCli.verifyBookOrderFiles(dir.path),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('otzaria_book_order.json'),
        ),
      ),
    );

    File(p.join(dir.path, 'otzaria_book_order.json')).writeAsStringSync('{}');
    ReleaseIndexBuilderCli.verifyBookOrderFiles(dir.path);
  });
}
