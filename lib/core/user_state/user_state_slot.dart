/// המשבצת שתחתיה נשמר מצב **פר-חלון** (סשן כרטיסיות, שולחן פעיל, גבולות).
abstract final class UserStateSlot {
  /// המשבצת של החלון הראשי. ⚠️ קבועה: הסשנים השמורים ממופתחים לפיה.
  /// חלונות Dart תופסים משבצות מ-2 (`ViewWindowRegistry.freeSlot`).
  static const int main = 1;
}
