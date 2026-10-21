import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// מבדיל לחיצה רגילה, בחירה בגרירה ולחיצות מרובות בלי להתחרות בבחירת הטקסט.
class EnhancedGestureDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onShiftClick;
  final VoidCallback? onCtrlClick;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onDragSelectionStart;
  final HitTestBehavior? behavior;

  /// תחום לחיצות משותף לקורא; ברירת המחדל היא רשימת הגלילה הקרובה.
  final Object? coordinationGroup;

  const EnhancedGestureDetector({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onShiftClick,
    this.onCtrlClick,
    this.onSecondaryTapDown,
    this.onDragSelectionStart,
    this.behavior,
    this.coordinationGroup,
  });

  /// מבטל לחיצה ממתינה בקורא; אותו pointer נשמר עבור לחיצה כפולה ומשולשת.
  static void cancelPendingTap(Object group, {int? exceptPointer}) {
    final pending = _EnhancedGestureDetectorState._pendingTaps[group];
    if (pending != null &&
        (exceptPointer == null || pending._tapPointer != exceptPointer)) {
      pending._cancelPendingTap();
    }
  }

  @override
  State<EnhancedGestureDetector> createState() =>
      _EnhancedGestureDetectorState();
}

class _EnhancedGestureDetectorState extends State<EnhancedGestureDetector> {
  Offset? _tapDownPosition;
  int? _tapDownButtons;
  static final _pendingTaps = Expando<_EnhancedGestureDetectorState>();
  ScrollPosition? _scrollPosition;
  Object? _pendingGroup;
  int? _tapPointer;
  Object? get _coordinationGroup => widget.coordinationGroup ?? _scrollPosition;
  Timer? _tapTimer;
  int _tapCount = 0;
  static const int _multiTapTimeout = 300; // זמן מקסימלי בין לחיצות רצופות
  static const double _dragThreshold = 5.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scrollPosition) {
      _cancelPendingTap();
      _scrollPosition = position;
    }
  }

  @override
  void didUpdateWidget(EnhancedGestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.coordinationGroup, widget.coordinationGroup)) {
      _cancelPendingTap();
    }
  }

  void _cancelPendingTap() {
    _tapTimer?.cancel();
    _tapTimer = null;
    _tapCount = 0;
    _tapDownPosition = null;
    _tapDownButtons = null;
    _tapPointer = null;
    final position = _scrollPosition;
    position?.removeListener(_cancelPendingTap);
    final group = _pendingGroup;
    if (group != null && identical(_pendingTaps[group], this)) {
      _pendingTaps[group] = null;
    }
    _pendingGroup = null;
  }

  void _scheduleTapTimeout() {
    _tapTimer?.cancel();
    final position = _scrollPosition;
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : null;
    position?.removeListener(_cancelPendingTap);
    _pendingGroup = _coordinationGroup;
    if (_pendingGroup != null) _pendingTaps[_pendingGroup!] = this;
    position?.addListener(_cancelPendingTap);
    _tapTimer = Timer(const Duration(milliseconds: _multiTapTimeout), () {
      final single =
          _tapCount == 1 &&
          mounted &&
          (box is! RenderBox ||
              origin == null ||
              (box.attached &&
                  (box.localToGlobal(Offset.zero) - origin).distance <=
                      _dragThreshold));
      _cancelPendingTap();
      if (single && mounted) widget.onSingleTap?.call();
    });
  }

  @override
  void deactivate() {
    _cancelPendingTap();
    super.deactivate();
  }

  @override
  void dispose() {
    _cancelPendingTap();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior ?? HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerMove: _handlePointerMove,
      onPointerCancel: (_) => _cancelPendingTap(),
      onPointerSignal: (_) => _cancelPendingTap(),
      child: widget.child,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    final group = _coordinationGroup;
    if (group != null) {
      final previous = _pendingTaps[group];
      if (!identical(previous, this)) previous?._cancelPendingTap();
    }
    if (event.buttons != kPrimaryMouseButton) _cancelPendingTap();
    _tapPointer = event.pointer;
    _tapDownPosition = event.localPosition;
    _tapDownButtons = event.buttons;

    if (event.buttons == kSecondaryMouseButton) {
      widget.onSecondaryTapDown?.call(
        TapDownDetails(
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_tapDownPosition != null && _tapDownButtons == kPrimaryMouseButton) {
      final distance = (event.localPosition - _tapDownPosition!).distance;
      if (distance > _dragThreshold) {
        widget.onDragSelectionStart?.call();
        _cancelPendingTap();
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_tapDownButtons != kPrimaryMouseButton) {
      _cancelPendingTap();
      return;
    }

    if (_tapDownPosition == null) {
      return;
    }

    final distance = (event.localPosition - _tapDownPosition!).distance;
    if (distance > _dragThreshold) {
      _cancelPendingTap();
      return;
    }

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (isShiftPressed) {
      _cancelPendingTap();
      widget.onShiftClick?.call();
      return;
    }

    // Ctrl (או Cmd ב-macOS) + לחיצה → הוספת/הסרת קטע מבחירה מרובה.
    final isCtrlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isCtrlPressed && widget.onCtrlClick != null) {
      _cancelPendingTap();
      widget.onCtrlClick!.call();
      return;
    }

    if (!(_tapTimer?.isActive ?? false)) _tapCount = 0;
    _tapCount++;
    if (_tapCount >= 3) {
      _cancelPendingTap();
      return;
    }
    _scheduleTapTimeout();
    if (_tapCount == 2) widget.onDoubleTap?.call();

    _tapDownPosition = null;
    _tapDownButtons = null;
  }
}
