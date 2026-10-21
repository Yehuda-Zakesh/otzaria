import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// [ItemScrollController] שמודיע למאזינים לפני כל קפיצה לאינדקס.
class JumpAwareItemScrollController extends ItemScrollController {
  final _beforeJumpListeners = ObserverList<VoidCallback>();
  var _silent = 0;

  void addBeforeJumpListener(VoidCallback listener) =>
      _beforeJumpListeners.add(listener);

  void removeBeforeJumpListener(VoidCallback listener) =>
      _beforeJumpListeners.remove(listener);

  /// מודיע למאזינים על ניווט שאינו עובר ברשימה (למשל קורא חיצוני).
  void notifyBeforeJump() {
    for (final listener in _beforeJumpListeners.toList()) {
      listener();
    }
  }

  /// מריץ את [move] בלי להודיע למאזינים: תיקון של ניווט שכבר הודיעו עליו,
  /// או גלילה ליעד שכבר במסך.
  T withoutNotifying<T>(T Function() move) {
    _silent++;
    try {
      return move();
    } finally {
      _silent--;
    }
  }

  @override
  Future<void> jumpToAsync({
    required int index,
    double alignment = 0,
    double offset = 0,
    TargetRectResolver? targetRectResolver,
  }) {
    if (_silent == 0) notifyBeforeJump();
    return super.jumpToAsync(
      index: index,
      alignment: alignment,
      offset: offset,
      targetRectResolver: targetRectResolver,
    );
  }

  @override
  Future<void> scrollTo({
    required int index,
    double alignment = 0,
    double offset = 0,
    TargetRectResolver? targetRectResolver,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
  }) {
    if (_silent == 0) notifyBeforeJump();
    return super.scrollTo(
      index: index,
      alignment: alignment,
      offset: offset,
      targetRectResolver: targetRectResolver,
      duration: duration,
      curve: curve,
    );
  }
}
