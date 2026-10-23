import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/window_role.dart';

/// האם הקוד הזה מריץ עבודה פר-תהליך (עדכונים, סנכרון, אינדוקס, הפעלות חיצוניות).
/// היום זה בדיוק `!WindowRole.isSecondary`; בלי נעילת "פעם אחת" — יש אתרים שנכנסים שוב.
class ProcessDuties {
  ProcessDuties({
    bool Function()? isProcessOwner,
    this.hostsPluginBackground = true,
  }) : _isProcessOwner = isProcessOwner ?? _notSecondaryWindow;

  static bool _notSecondaryWindow() => !WindowRole.isSecondary;

  final bool Function() _isProcessOwner;

  /// נקרא בכל פעם מחדש, ולכן משקף שינוי של [WindowRole.isSecondary] אחרי היצירה.
  bool get isProcessOwner => _isProcessOwner();

  /// האם החלון מארח את סביבת התוספים שברקע. היום כל חלון הוא תהליך משלו ולכן
  /// תמיד כן; חלון נוסף באותו isolate יעביר `false` כדי לא לשכפל אותה.
  final bool hostsPluginBackground;

  static final ProcessDuties _default = ProcessDuties();
  static ProcessDuties? _override;

  /// המופע של התהליך, נגיש גם בלי `BuildContext` (בלוקים, שירותים סטטיים).
  static ProcessDuties get current => _override ?? _default;

  /// המופע של החלון מ-`WindowScopeProviders`; בלעדיו — [current].
  static ProcessDuties of(BuildContext context) {
    try {
      return context.read<ProcessDuties>();
    } on ProviderNotFoundException {
      return current;
    }
  }

  /// מחליף את [current] בבדיקות; `null` מחזיר את ברירת המחדל.
  @visibleForTesting
  static set debugOverride(ProcessDuties? duties) => _override = duties;
}
