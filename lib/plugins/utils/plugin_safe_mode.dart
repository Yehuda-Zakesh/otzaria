import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/startup_crash_counter.dart';

/// מצב בטוח משבית תוספים בסשן בלבד ושומר את בחירת המשתמש.
class PluginSafeMode {
  PluginSafeMode._();

  static final ValueNotifier<bool> active = ValueNotifier(false);

  static bool get isActive => active.value;

  static Future<void> ready = SynchronousFuture<void>(null);
  static const String readyRequest = 'pluginSafeModeReady';

  /// ההחלטה מתקבלת אחרי חשיפת החלון ולפני קריאת מצב התוספים.
  static Future<void> initializeSession({
    required bool isSecondary,
    Future<bool> Function()? waitForPrimary,
    void Function(Object, StackTrace)? onError,
  }) async {
    try {
      if (isSecondary) {
        if (waitForPrimary == null) {
          throw StateError('Primary decision required');
        }
        active.value = await waitForPrimary();
      } else if (!StartupCrashCounter.recordedThisProcess) {
        final earlyEnds = await StartupCrashCounter.recordLaunch();
        if (earlyEnds >= StartupCrashCounter.safeModeThreshold && !isActive) {
          active.value = true;
          enteredAfterCrashes = true;
        }
      }
    } catch (error, stackTrace) {
      active.value = true;
      if (onError != null) {
        onError(error, stackTrace);
      } else {
        debugPrint('Plugin safe mode initialization failed: $error');
      }
    }
  }

  /// Safe mode was turned on because the previous launches crashed while
  /// starting, not by the user.
  static bool enteredAfterCrashes = false;

  /// קריאת דגל הפעלה אינה נוגעת בקבצים.
  static void initFromArgs(List<String> args) {
    active.value = args.any(isSafeModeFlag);
  }

  static Future<void> set(bool value) async => active.value = value;

  @visibleForTesting
  static void resetForTesting() {
    active.value = false;
    enteredAfterCrashes = false;
    ready = SynchronousFuture<void>(null);
  }
}

/// Whether [arg] is `--safe-mode` (also `/safe-mode`, bare, or with `_`).
bool isSafeModeFlag(String arg) =>
    arg
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^(--|/)'), '')
        .replaceAll('_', '-') ==
    'safe-mode';
