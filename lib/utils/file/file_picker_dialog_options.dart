import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_darwin/file_picker_darwin.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/dialog_owner.dart';
import 'package:windows_file_picker/windows_file_picker.dart';

/// דיאלוגי המערכת נפתחים מודאליים מעל חלון האפליקציה. ההגדרה נפרדת לכל
/// פלטפורמה, ושתיהן חייבות להיקבע יחד — אחרת הדיאלוג מודאלי רק באחת מהן.
/// ב-Windows הבעלים הוא החלון של [context] (או הפעיל), ולא החלון שבחזית.
WindowsOptions modalWindowsOptions([BuildContext? context]) =>
    FilePickerWindowsOptions(
      lockParentWindow: true,
      parentWindowHandle: DialogOwner.hwnd(context: context),
    );

const kModalLinuxOptions = LinuxOptions(lockParentWindow: true);

/// שומר בעלות לכל בקשת בורר בנפרד, גם כשבדיקת הרשאות בנייטיב ממתינה.
Future<T?> withFilePickerOwner<T>(
  BuildContext? context,
  Future<T?> Function() action,
) {
  if (context != null && !context.mounted) return Future.value();
  if (Platform.isWindows &&
      context != null &&
      DialogOwner.hwnd(context: context) == null) {
    return Future.value();
  }
  final viewId = context == null ? null : View.maybeOf(context)?.viewId;
  return Platform.isMacOS
      ? FilePickerDarwin.withWindow(viewId, action)
      : action();
}
