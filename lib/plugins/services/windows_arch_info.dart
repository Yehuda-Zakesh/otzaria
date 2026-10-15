import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// זיהוי ארכיטקטורת Windows on ARM — הן ריצה נייטיבית והן אמולציית x64.
///
/// באמולציה WebView2 מסרב ליצור controller במסלול הקומפוזיציה שבו התוספים
/// משתמשים, וכל תוסף עולה ריק. הזיהוי מאפשר להסביר זאת למשתמש, ומשמש גם
/// את מנגנון העדכון לבחירת המתקין המתאים למעבד.
class WindowsArchInfo {
  static const _imageFileMachineArm64 = 0xaa64;

  /// `true` כשהתהליך הנוכחי הוא x64 אך המעבד עצמו ARM64.
  ///
  /// בתהליך x64 מאומלץ משתני הסביבה מתארים את המעבד המדומה, לכן מקור האמת
  /// הוא [IsWow64Process2] שמחזיר את ארכיטקטורת המארח.
  static bool get isEmulatedOnArm {
    if (!Platform.isWindows) return false;
    return resolveEmulatedOnArm(
      Platform.environment,
      nativeMachine: _nativeMachine(),
    );
  }

  /// `true` על כל מחשב ARM — בין אם התהליך נייטיבי ובין אם מאומל.
  /// זה הקריטריון לבחירת מתקין העדכון: המעבד קובע, לא התהליך הנוכחי.
  static bool get isWindowsOnArm {
    if (!Platform.isWindows) return false;
    return resolveWindowsOnArm(
      Platform.environment,
      nativeMachine: _nativeMachine(),
    );
  }

  @visibleForTesting
  static bool resolveEmulatedOnArm(
    Map<String, String> environment, {
    int? nativeMachine,
  }) {
    final process = environment['PROCESSOR_ARCHITECTURE']?.toUpperCase();
    if (nativeMachine == _imageFileMachineArm64) {
      return process != null && !process.startsWith('ARM');
    }
    final native = environment['PROCESSOR_ARCHITEW6432']?.toUpperCase();
    if (native == null || native.isEmpty) return false;
    return native.startsWith('ARM') &&
        process != null &&
        !process.startsWith('ARM');
  }

  @visibleForTesting
  static bool resolveWindowsOnArm(
    Map<String, String> environment, {
    int? nativeMachine,
  }) {
    if (nativeMachine == _imageFileMachineArm64) return true;
    final process = environment['PROCESSOR_ARCHITECTURE']?.toUpperCase();
    if (process != null && process.startsWith('ARM')) return true;
    return resolveEmulatedOnArm(environment);
  }

  static int? _nativeMachine() {
    final processMachine = calloc<ffi.Uint16>();
    final nativeMachine = calloc<ffi.Uint16>();
    try {
      final result = IsWow64Process2(
        GetCurrentProcess(),
        processMachine,
        nativeMachine,
      );
      return result.value ? nativeMachine.value : null;
    } catch (_) {
      return null;
    } finally {
      calloc.free(processMachine);
      calloc.free(nativeMachine);
    }
  }
}
