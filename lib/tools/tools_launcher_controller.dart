import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';

/// פותח את פאנל הכלים של חלון שנלכד מראש, או של החלון הפעיל כברירת מחדל.
class ToolsLauncherController {
  ToolsLauncherController._();

  static final ToolsLauncherController instance = ToolsLauncherController._();

  final _openers = Expando<void Function()>();

  /// הפותח של החלון הנוכחי. `null` כשהמסך שלו אינו מורכב.
  void Function()? get opener => _openers[AppWindowKeys.current];
  set opener(void Function()? value) => _openers[AppWindowKeys.current] = value;

  /// נקרא על-ידי `MainWindowScreen` של החלון [keys].
  void register(AppWindowKeys keys, void Function() opener) =>
      _openers[keys] = opener;

  /// מסיר את [opener] רק אם הוא עדיין הרשום (השוואה ב-== — tear-off חדש בכל גישה).
  void unregister(AppWindowKeys keys, void Function() opener) {
    if (_openers[keys] == opener) _openers[keys] = null;
  }

  @visibleForTesting
  int openCount = 0;

  void open({AppWindowKeys? windowKeys}) {
    openCount++;
    _openers[windowKeys ?? AppWindowKeys.current]?.call();
  }
}
