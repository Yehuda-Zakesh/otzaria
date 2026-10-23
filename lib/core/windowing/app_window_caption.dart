import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_drag_to_move_area.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:window_manager/window_manager.dart' show WindowCaptionButton;

/// כמו `WindowCaption` של window_manager (בלי כותרת), אבל הכפתורים ומצב
/// ה-maximize באים מה-[AppWindowScope] ולא מה-singleton.
class AppWindowCaption extends StatefulWidget {
  const AppWindowCaption({super.key, this.backgroundColor, this.brightness});

  final Color? backgroundColor;
  final Brightness? brightness;

  @override
  State<AppWindowCaption> createState() => _AppWindowCaptionState();
}

class _AppWindowCaptionState extends State<AppWindowCaption> {
  AppWindowController? _window;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = AppWindowScope.controllerOf(context);
    if (identical(window, _window)) return;
    _window?.stateChanges.removeListener(_onStateChanged);
    _window = window..stateChanges.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _window?.stateChanges.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final window = _window!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            widget.backgroundColor ??
            (widget.brightness == Brightness.dark
                ? const Color(0xff1C1C1C)
                : Colors.transparent),
      ),
      child: Row(
        children: [
          const Expanded(
            child: AppDragToMoveArea(child: SizedBox(height: double.infinity)),
          ),
          // המקור בודק isMinimized ומשחזר; כפתור בחלון ממוזער אינו לחיץ.
          WindowCaptionButton.minimize(
            brightness: widget.brightness,
            onPressed: window.minimize,
          ),
          FutureBuilder<bool>(
            future: window.isMaximized(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return WindowCaptionButton.unmaximize(
                  brightness: widget.brightness,
                  onPressed: window.unmaximize,
                );
              }
              return WindowCaptionButton.maximize(
                brightness: widget.brightness,
                onPressed: window.maximize,
              );
            },
          ),
          WindowCaptionButton.close(
            brightness: widget.brightness,
            onPressed: window.close,
          ),
        ],
      ),
    );
  }
}
