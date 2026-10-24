import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// האם החלון הזה מריץ עבודה פר-תהליך (עדכונים, סנכרון, אינדוקס, הפעלות
/// חיצוניות). החלון הראשי כן; חלון Dart ([ProcessDuties.of]) לא.
class ProcessDuties {
  ProcessDuties({
    bool Function()? isProcessOwner,
    this.hostsPluginBackground = true,
  }) : _isProcessOwner = isProcessOwner ?? _owner;

  static bool _owner() => true;

  final bool Function() _isProcessOwner;

  bool get isProcessOwner => _isProcessOwner();

  /// האם החלון מארח את סביבת התוספים שברקע; חלון Dart לא, כדי לא לשכפל אותה.
  final bool hostsPluginBackground;

  static final ProcessDuties _default = ProcessDuties();
  static ProcessDuties? _override;

  /// מופע החלון הראשי, שהוא בעל התהליך; נגיש גם בלי `BuildContext`.
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
