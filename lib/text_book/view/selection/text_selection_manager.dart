import 'package:flutter/material.dart';

/// לבדיקות: נקרא בכל קביעת עוגן, עם השורה שנקבעה.
@visibleForTesting
void Function(int index)? debugOnSelectionAnchor;

/// מנהל מצב בחירת טקסט זמני (Selection-only mode)
/// מאפשר בחירת טקסט לצורך העתקה בלבד, ללא עריכה
class TextSelectionManager extends ChangeNotifier {
  /// נקודת העיגון לבחירה (anchor point)
  int? _anchorIndex;

  /// האם נמצאים במצב בחירה זמני
  bool _isInSelectionMode = false;

  bool get isInSelectionMode => _isInSelectionMode;

  /// קביעת anchor point (נקודת התחלה לבחירה)
  void setAnchor(int index) {
    debugOnSelectionAnchor?.call(index);
    _anchorIndex = index;
    _isInSelectionMode = true;
    notifyListeners();
  }

  /// כניסה למצב בחירה עם double-click
  /// הערה: הפיצ'ר לא מומש במלואו בגלל מגבלות Flutter
  void enterDoubleClickMode(int index) {
    _anchorIndex = index;
    _isInSelectionMode = true;
    notifyListeners();
  }

  /// יציאה ממצב בחירה
  void exitSelectionMode() {
    _anchorIndex = null;
    _isInSelectionMode = false;
    notifyListeners();
  }

  /// בדיקה אם יש anchor פעיל
  bool hasAnchor() => _anchorIndex != null;
}

/// Intent לניקוי בחירה
class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}
