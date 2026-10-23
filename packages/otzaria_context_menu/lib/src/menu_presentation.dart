import 'package:flutter/material.dart';

import 'menu_metrics.dart';

typedef AppMenuIconBuilder =
    Widget Function(
      BuildContext context,
      IconData icon,
      double size,
      Color? color,
      bool mirrorForRtl,
    );

typedef AppMenuMarkBuilder =
    Widget Function(
      BuildContext context,
      double size,
      Color? color,
    );

typedef AppMenuArrowBuilder =
    Widget Function(
      BuildContext context,
      bool openToRight,
      double size,
      Color? color,
    );

typedef MenuEscapeRegistrar = VoidCallback Function(OnKeyEventCallback handler);

typedef MenuPreviewWrapper =
    Widget Function(
      BuildContext context,
      WidgetBuilder previewBuilder,
      VoidCallback onPinned,
      Widget child,
    );

/// נתוני הצגה שאינם תלויים במערכת העיצוב של היישום המארח.
class MenuPresentation {
  const MenuPresentation({
    required this.metrics,
    required this.borderRadius,
    required this.iconBuilder,
    required this.selectedMarkBuilder,
    required this.submenuArrowBuilder,
    required this.downArrowBuilder,
  });

  final AppMenuMetrics metrics;
  final BorderRadius borderRadius;
  final AppMenuIconBuilder iconBuilder;
  final AppMenuMarkBuilder selectedMarkBuilder;
  final AppMenuArrowBuilder submenuArrowBuilder;
  final AppMenuMarkBuilder downArrowBuilder;
}
