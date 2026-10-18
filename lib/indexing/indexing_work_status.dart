import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/work_status/work_status_item.dart';

/// מזהה פריט חיווי העבודה של האינדוקס.
const kIndexingWorkStatusId = 'indexing';

/// פריט חיווי העבודה לאינדוקס, כולל לחצני השהיה/המשך ומצב חסכוני
/// (issue #834).
WorkStatusItem indexingWorkStatusItem(
  IndexingInProgress state, {
  required VoidCallback onTogglePause,
  required VoidCallback onToggleEconomy,
  VoidCallback? onTap,
}) {
  final total = state.totalBooks ?? 0;
  final processed = state.booksProcessed ?? 0;
  // שלב האיחוד ארוך וללא התקדמות מדידה; מונה קפוא על הספר האחרון נראה
  // כתקיעה (issue #1021), ולכן הוא מוחלף בהודעה ובמד בלתי-מוגדר.
  if (state.isFinalizing) {
    return WorkStatusItem(
      id: kIndexingWorkStatusId,
      title: 'אינדוקס ספרים',
      message: 'מסיים ומאחד את קבצי האינדקס',
      detail: 'כל הספרים אונדקסו; הפעולה עשויה להימשך מספר דקות',
      onTap: onTap,
    );
  }
  final String message;
  if (state.isScanning) {
    message = state.isPaused
        ? 'בדיקת הספרים מושהית'
        : 'בודק אילו ספרים דורשים עדכון באינדקס';
  } else {
    message = state.isPaused ? 'האינדוקס מושהה' : 'התוכנה בתהליך אינדוקס';
  }
  return WorkStatusItem(
    id: kIndexingWorkStatusId,
    title: 'אינדוקס ספרים',
    message: message,
    detail: 'התקדמות: $processed/$total',
    progress: total > 0 ? (processed / total).clamp(0.0, 1.0) : null,
    onTap: onTap,
    actions: [
      WorkStatusAction(
        label: state.isPaused ? 'המשך' : 'השהה',
        icon: state.isPaused
            ? FluentIcons.play_24_regular
            : FluentIcons.pause_24_regular,
        tooltip: state.isPaused ? null : 'ההשהיה נכנסת לתוקף בסיום הספר הנוכחי',
        onPressed: onTogglePause,
      ),
      // בשלב הבדיקה אין כתיבה למנוע, ולכן אין למצב החסכוני מה להאט.
      if (!state.isScanning)
        WorkStatusAction(
          label: 'מצב חסכוני',
          icon: FluentIcons.battery_saver_24_regular,
          tooltip: 'מאט את האינדוקס ומפחית את העומס על המחשב',
          emphasized: state.isEconomy,
          onPressed: onToggleEconomy,
        ),
    ],
  );
}
