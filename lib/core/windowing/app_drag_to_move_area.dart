import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';

/// כמו `DragToMoveArea` של window_manager, אבל גורר את החלון של ה-[AppWindowScope]
/// שמעליו ולא את ה-singleton — כדי שחלון Dart יגרור את עצמו.
class AppDragToMoveArea extends StatelessWidget {
  const AppDragToMoveArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => AppWindowScope.controllerOf(context).startDragging(),
      onDoubleTap: () async {
        final window = AppWindowScope.controllerOf(context);
        if (await window.isMaximized()) {
          await window.unmaximize();
        } else {
          await window.maximize();
        }
      },
      child: child,
    );
  }
}
