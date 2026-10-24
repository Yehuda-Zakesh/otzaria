import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/services/startup_crash_counter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dataRoot;

  setUp(() {
    dataRoot = Directory.systemTemp.createTempSync('safe-mode');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    StartupCrashCounter.resetForTesting();
  });

  tearDown(() {
    PluginSafeMode.resetForTesting();
    AppPaths.debugOverrideDataRootPath(null);
    dataRoot.deleteSync(recursive: true);
  });

  File marker() => File(p.join(dataRoot.path, 'safe_mode_session.json'));

  test('the flag is read in its accepted spellings', () {
    for (final arg in ['--safe-mode', '/safe-mode', '--SAFE_MODE']) {
      expect(isSafeModeFlag(arg), isTrue, reason: arg);
    }
    expect(isSafeModeFlag('--dev-plugins'), isFalse);
    expect(isSafeModeFlag('otzaria://plugin/install'), isFalse);
  });

  test('initFromArgs sets the mode without touching files', () {
    PluginSafeMode.initFromArgs(const ['--safe-mode']);
    expect(PluginSafeMode.isActive, isTrue);
    expect(marker().existsSync(), isFalse);

    PluginSafeMode.initFromArgs(const []);
    expect(PluginSafeMode.isActive, isFalse);
  });

  test(
    'unwritable or undeletable legacy marker cannot affect session choices',
    () async {
      final blocked = Directory(marker().path)..createSync();
      File(p.join(blocked.path, 'child')).writeAsStringSync('keep');
      await PluginSafeMode.initializeSession();
      for (final mode in [true, false]) {
        await PluginSafeMode.set(mode);
        await PluginSafeMode.initializeSession();
        expect(PluginSafeMode.isActive, mode);
        expect(await blocked.exists(), isTrue);
        expect(
          await File(p.join(blocked.path, 'child')).readAsString(),
          'keep',
        );
      }
    },
  );

  test(
    'primary preserves the session choice on soft restart',
    () async {
      await PluginSafeMode.initializeSession();
      final attempts = File(
        p.join(dataRoot.path, StartupCrashCounter.attemptsFileName),
      );
      expect(await attempts.readAsString(), '1');
      await PluginSafeMode.set(true);
      await PluginSafeMode.initializeSession();
      expect(PluginSafeMode.isActive, isTrue);
      await PluginSafeMode.set(false);
      await PluginSafeMode.initializeSession();
      expect(PluginSafeMode.isActive, isFalse);
      expect(await attempts.readAsString(), '1');
    },
  );

  test(
    'two failed launches decide safe mode before completion',
    () async {
      File(
        p.join(dataRoot.path, StartupCrashCounter.attemptsFileName),
      ).writeAsStringSync('2');
      await PluginSafeMode.initializeSession();
      expect(PluginSafeMode.isActive, isTrue);
      expect(PluginSafeMode.enteredAfterCrashes, isTrue);
      expect(marker().existsSync(), isFalse);
    },
  );

  test('unwritable crash counter is nonfatal', () async {
    Directory(
      p.join(dataRoot.path, StartupCrashCounter.attemptsFileName),
    ).createSync();
    await expectLater(
      PluginSafeMode.initializeSession(),
      completes,
    );
  });
}
