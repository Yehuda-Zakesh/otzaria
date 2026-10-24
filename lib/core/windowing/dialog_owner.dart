import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';

/// החלון שדיאלוג מערכת (קבצים, הדפסה) צריך להיות מודאלי אליו. עם חלונות Dart
/// ה-runner מכיר רק את הראשי, שעשוי להיות מוסתר — ואז הדיאלוג חסר בעלים נכון.
abstract final class DialogOwner {
  static int? _mainWindowHwnd;

  /// ה-HWND של החלון הראשי; נקבע בעלייה, אחרי window_manager.
  static set mainWindowHwnd(int? hwnd) => _mainWindowHwnd = hwnd;

  /// החלון של [context], ובלעדיו — החלון הפעיל. מקור שנסגר אינו
  /// מוחלף בחלון אחר; `null` מציין שאין בעלים זמין.
  static int? hwnd({
    BuildContext? context,
    ViewWindowRegistry? registry,
    bool? isMainShown,
  }) {
    if (context != null && !context.mounted) return null;
    final id = context != null
        ? AppWindowKeys.of(context).id
        : AppWindowKeys.current.id;
    if (id != AppWindowId.primary) {
      final entry = (registry ?? ViewWindowRegistry.instance).windows
          .where((w) => w.id == id)
          .firstOrNull;
      if (context != null && (entry == null || entry.isClosing)) return null;
      final hwnd = entry?.handle.hwnd;
      if (hwnd != null) return hwnd;
      if (context != null) return null;
    }
    // ראשי מוסתר אינו בעלים: דיאלוג שלו לא היה מופיע מעל חלון שרואים.
    final mainShown = isMainShown ?? InProcessTabDrops.instance.isMainShown;
    return mainShown ? _mainWindowHwnd : null;
  }

  @visibleForTesting
  static void resetForTest() => _mainWindowHwnd = null;
}
