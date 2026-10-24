import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget לניהול קיצורי מקלדת בדיאלוגים.
///
/// מספק:
/// - חיצים ◄► למעבר בין כפתורים
/// - Enter ללחיצה על הכפתור הממוקד
/// - Escape לביטול
/// - Enter בשדה טקסט → שליחת הטופס
class DialogKeyboardNavigator extends StatelessWidget {
  final Widget child;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final int focusedIndex;
  final ValueChanged<int> onFocusChange;
  final FocusNode? textFieldFocusNode;
  final bool handleEnterKey;

  const DialogKeyboardNavigator({
    super.key,
    required this.child,
    this.onConfirm,
    this.onCancel,
    required this.focusedIndex,
    required this.onFocusChange,
    this.textFieldFocusNode,
    this.handleEnterKey = true,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: false,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // אם הפוקוס בשדה הטקסט, Enter שולח את הטופס
        if (textFieldFocusNode?.hasFocus ?? false) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (!handleEnterKey) {
              return KeyEventResult.ignored;
            }
            onConfirm?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // חיצים ◄► — מעבר בין כפתורים
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onFocusChange(focusedIndex == 0 ? 1 : 0);
          return KeyEventResult.handled;
        }

        // Enter — לחיצה על הכפתור הממוקד
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (!handleEnterKey) {
            return KeyEventResult.ignored;
          }
          if (focusedIndex == 1) {
            onConfirm?.call();
          } else {
            onCancel?.call();
          }
          return KeyEventResult.handled;
        }

        // Escape — ביטול
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          onCancel?.call();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DialogNavigationMixin
// ─────────────────────────────────────────────────────────────────────────────

/// Mixin נוח לשימוש ב-[DialogKeyboardNavigator] מתוך StatefulWidget.
///
/// שימוש:
/// ```dart
/// class _MyDialogState extends State<MyDialog>
///     with DialogNavigationMixin<MyDialog> {
///
///   @override
///   Widget build(BuildContext context) {
///     return buildKeyboardNavigator(
///       child: ...,
///       onConfirm: _submit,
///       onCancel: () => Navigator.of(context).pop(),
///     );
///   }
/// }
/// ```
mixin DialogNavigationMixin<T extends StatefulWidget> on State<T> {
  /// 0 = Cancel, 1 = Confirm (ברירת מחדל: Confirm ממוקד)
  int focusedButtonIndex = 1;

  Widget buildKeyboardNavigator({
    required Widget child,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
    FocusNode? textFieldFocusNode,
    bool handleEnterKey = true,
  }) {
    return DialogKeyboardNavigator(
      focusedIndex: focusedButtonIndex,
      onFocusChange: (index) => setState(() => focusedButtonIndex = index),
      onConfirm: onConfirm,
      onCancel: onCancel,
      textFieldFocusNode: textFieldFocusNode,
      handleEnterKey: handleEnterKey,
      child: child,
    );
  }
}
