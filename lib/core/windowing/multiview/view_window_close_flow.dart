import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

/// שואל אם מותר לסגור את [tabs], בתוך החלון של [context].
typedef ViewWindowCloseConfirm =
    Future<bool> Function(BuildContext context, List<OpenedTab> tabs);

/// סגירת חלון Dart: רק מה ששייך לחלון הזה. העבודה של התהליך (שומר
/// התוספים, טיוטות התיקונים, יציאה) שייכת לחלון הראשי ואינה רצה כאן.
class ViewWindowCloseFlow {
  ViewWindowCloseFlow({
    required this.entry,
    ViewWindowCloseConfirm? confirm,
    Future<void> Function()? flush,
    Future<void> Function(int slot)? discardSession,
    this._opener,
  }) : _confirm = confirm ?? _confirmUnsavedTabs,
       _flush = flush ?? PreCloseRegistry.runAll,
       _discardSession = discardSession ?? WindowSessionStore.instance.delete;

  final ViewWindowEntry entry;
  final ViewWindowCloseConfirm _confirm;
  final Future<void> Function() _flush;
  final Future<void> Function(int slot) _discardSession;
  final ViewWindowOpener? _opener;
  bool _running = false;

  static Future<bool> _confirmUnsavedTabs(
    BuildContext context,
    List<OpenedTab> tabs,
  ) => confirmCloseTabs(
    context,
    tabs,
    subtitle: unsavedChangesWindowCloseSubtitle,
  );

  /// מחזיר false כשהמשתמש ביטל; לחיצה חוזרת בזמן ריצה אינה עושה דבר.
  Future<bool> run() async {
    if (_running) return false;
    _running = true;
    try {
      final opener = _opener ?? ViewWindowOpener.instance;
      return await opener.serializeClose(() async {
        final endProcess = opener.endProcess;
        if (endProcess != null && await opener.isLastVisibleWindow(entry)) {
          // החלון האחרון על המסך: יציאה מהתוכנה, עם השאלות של יציאה. אם חזרה — בוטלה.
          AppWindowKeys.activateWindow(entry.id);
          await endProcess();
          return false;
        }
        final context = entry.keys.navigator.currentContext;
        if (context != null && context.mounted) {
          final tabs = context.read<TabsBloc>().state.tabs;
          if (!await _confirm(context, tabs)) return false;
        }
        try {
          // שוטף את כל החלונות; כתיבה מיותרת בחלון אחר אינה מזיקה.
          await _flush();
        } on PreCloseFlushFailure catch (e) {
          debugPrint('view window close: flush failed: $e');
        }
        await opener.rememberClosed(entry.slot);
        // סגירה מכוונת מוחקת את הסשן; קודם endSession, ששמירה באמצע לא תחזיר אותו.
        entry.endSession();
        try {
          await _discardSession(entry.slot);
        } catch (e) {
          // השורה תאומץ בהפעלה הבאה; החלון נסגר בכל מקרה.
          debugPrint('view window close: discard failed: $e');
        }
        entry.handle.destroy();
        return true;
      });
    } finally {
      _running = false;
    }
  }
}
