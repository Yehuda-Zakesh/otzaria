import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/dialogs/confirmation_dialog.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';

/// יציאה ממצב בטוח לאחר אישור המשתמש.
Future<void> restartNormally(BuildContext context) async {
  final confirmed = await showConfirmationDialog(
    context: context,
    title: 'יציאה ממצב בטוח',
    content: 'אוצריא תופעל מחדש כרגיל, והתוספים הפעילים ייטענו שוב.',
    confirmText: context.settingsText('הפעל מחדש כרגיל'),
  );
  if (confirmed != true || !context.mounted) return;
  await _restart(context, safeMode: false);
}

Future<void> _restart(BuildContext context, {required bool safeMode}) async {
  await PluginSafeMode.set(safeMode);
  PluginSafeMode.enteredAfterCrashes = false;
  await resetRuntimeStateForAppRestart();
  if (!context.mounted) return;
  MultiWindowService.restartPeers(pluginSafeMode: safeMode);
  RestartWidget.restartApp(
    context,
    afterRestart: WebViewEnvironmentHolder.disposeForAppRestart,
  );
}

/// Explains that safe mode started on its own after crashes while starting,
/// and offers a normal restart.
Future<void> showSafeModeAfterCrashesDialog(BuildContext context) async {
  final restartNormally = await showConfirmationDialog(
    context: context,
    title: 'אוצריא הופעלה במצב בטוח',
    content:
        'התוכנה נסגרה באופן לא צפוי פעמיים ברציפות בזמן הפתיחה, ולכן הופעלה '
        'הפעם בלי תוספים. אם תוסף גורם לתקלה, אפשר להשבית אותו בהגדרות ← '
        'ניהול כלים, ואחר כך להפעיל מחדש כרגיל.',
    cancelText: 'הישאר במצב בטוח',
    confirmText: context.settingsText('הפעל מחדש כרגיל'),
  );
  if (restartNormally == true && context.mounted) {
    await _restart(context, safeMode: false);
  }
}

/// Title bar chip shown while safe mode is on; tapping it offers a normal
/// restart.
class SafeModeTitleBarIndicator extends StatelessWidget {
  const SafeModeTitleBarIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PluginSafeMode.active,
      builder: (context, active, _) => !active
          ? const SizedBox.shrink()
          : BarButton.text(
              text: context.settingsText('מצב בטוח'),
              icon: FluentIcons.shield_24_regular,
              onPressed: () => restartNormally(context),
            ),
    );
  }
}
