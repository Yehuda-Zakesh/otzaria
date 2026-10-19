import 'package:flutter/foundation.dart';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/settings/dialogs/backup_restore_flow.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// הודעה בעלייה כשהמסדים האישיים נמחקו מבחוץ (issue #2610). בלעדיה התוכנה
/// יוצרת מסדים ריקים וממשיכה בשקט כאילו הותקנה זה עתה.
class PersonalDataMissingWarning {
  static bool _pending = false;

  static const title = 'הנתונים האישיים לא נמצאו';
  static const restoreText = 'שחזר מהגיבוי האחרון';

  @visibleForTesting
  static void debugReset() => _pending = false;

  /// נקרא מייד אחרי פתיחת `user_state.db`, לפני שמסדים אחרים נוצרים.
  static Future<void> detect() async {
    if (!UserStateDatabase.instance.createdOnOpen) return;
    try {
      _pending = await AppPaths.personalDatabasesWiped();
    } catch (error) {
      if (kDebugMode) debugPrint('Personal data check failed: $error');
    }
  }

  /// מוצג פעם אחת, אחרי שהחלון נחשף, ורק כשבגיבוי האחרון יש נתונים.
  static Future<void> showIfNeeded() async {
    if (!_pending) return;
    _pending = false;
    if (!await BackupService.latestBackupHasUserData()) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final restore = await showTwoActionsDialog(
      context: context,
      title: title,
      content:
          'תיקיית המסדים האישיים של התוכנה חסרה או ריקה, אף שהתוכנה כבר '
          'הייתה בשימוש במחשב הזה, ולכן נוצרו מסדים חדשים וריקים.\n\n'
          'בתיקיית הגיבוי נמצא גיבוי שיש בו נתונים, ואפשר לשחזר ממנו עכשיו '
          'או מאוחר יותר בהגדרות ← מערכת ← גיבוי ושחזור.',
      cancelText: 'לא עכשיו',
      confirmText: restoreText,
    );
    if (restore != true || !context.mounted) return;
    await BackupRestoreFlow.restoreLatest(context);
  }
}
