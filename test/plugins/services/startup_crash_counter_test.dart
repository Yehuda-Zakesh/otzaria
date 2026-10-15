import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/services/startup_crash_counter.dart';

void main() {
  late Directory dataRoot;

  setUp(() {
    dataRoot = Directory.systemTemp.createTempSync('startup-crashes');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    StartupCrashCounter.resetForTesting();
  });

  tearDown(() {
    AppPaths.debugOverrideDataRootPath(null);
    dataRoot.deleteSync(recursive: true);
  });

  /// A new process: the per-process guard starts over.
  Future<int> launch() {
    StartupCrashCounter.resetForTesting();
    return StartupCrashCounter.recordLaunch();
  }

  test('counts launches that never became stable', () async {
    expect(await launch(), 0);
    expect(await launch(), 1);
    expect(
      await launch(),
      greaterThanOrEqualTo(StartupCrashCounter.safeModeThreshold),
    );
  });

  test('a stable run or a normal exit starts the count over', () async {
    await launch();
    await StartupCrashCounter.markStable();
    expect(await launch(), 0);

    await launch();
    StartupCrashCounter.markStableSync();
    expect(await launch(), 0);
  });

  test('a soft restart in the same process is not a new launch', () async {
    await launch();
    expect(await StartupCrashCounter.recordLaunch(), 0);
    expect(await launch(), 1);
  });
}
