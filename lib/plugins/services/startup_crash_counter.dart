import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// Counts launches that ended before Otzaria ran stably, so that repeated
/// crashes while starting lead to safe mode instead of a loop.
///
/// A launch is recorded before plugins load and cleared once the app has run
/// for [stableAfter] after the window appeared, or on a normal exit.
class StartupCrashCounter {
  StartupCrashCounter._();

  static const int safeModeThreshold = 2;
  static const Duration stableAfter = Duration(seconds: 20);
  static const String attemptsFileName = 'startup_attempts.txt';

  static bool _recorded = false;

  static bool get recordedThisProcess => _recorded;

  /// Records this launch and returns how many launches right before it ended
  /// early. Only the first call per process counts.
  static Future<int> recordLaunch() async {
    if (_recorded) return 0;
    _recorded = true;
    try {
      final file = await _file();
      final previous = await file.exists()
          ? int.tryParse((await file.readAsString()).trim()) ?? 0
          : 0;
      await file.writeAsString('${previous + 1}', flush: true);
      return previous;
    } catch (error) {
      debugPrint('Startup crash counter failed: $error');
      return 0;
    }
  }

  static Future<void> markStable() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Startup crash counter reset failed: $error');
    }
  }

  /// For the window close handler, which cannot await.
  static void markStableSync() {
    final root = AppPaths.cachedDataRootPath;
    if (root == null) return;
    try {
      final file = File(p.join(root, attemptsFileName));
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static Future<File> _file() async =>
      File(p.join(await AppPaths.getDataRootPath(), attemptsFileName));

  @visibleForTesting
  static void resetForTesting() => _recorded = false;
}
