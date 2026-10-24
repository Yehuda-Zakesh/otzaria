// lib/widgets/layout/floating_panel.dart

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// רוחב מינימלי של פאנל צד בלוח שנה ובמסכים אחרים
const double kSidePanelWidth = 340.0;

/// רוחב מינימלי של תוכן ראשי לצד פאנל צד
const double kMainPanelMinWidth = 500.0;

/// סך הרוחב המינימלי להצגת פאנל צד ותוכן ראשי זה לצד זה
const double kSideBySideMinWidth = kSidePanelWidth + kMainPanelMinWidth;

/// פאנל צף בסגנון M3 — elevation + shadow + clip.
class FloatingPanel extends StatelessWidget {
  /// התוכן בתוך הפאנל
  final Widget child;

  /// גובה ה-elevation (M3 tonal + shadow) — ברירת מחדל: 2
  final double elevation;

  /// ריפוד פנימי אופציונלי
  final EdgeInsetsGeometry? padding;

  /// דריסת צבע הפאנל (אופציונלי)
  final Color? color;

  /// דריסת צבע הצל (אופציונלי) — ברירת מחדל: shadow עם 10% אופקסיטי
  final Color? shadowColor;

  const FloatingPanel({
    super.key,
    required this.child,
    this.elevation = 2,
    this.padding,
    this.color,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final panelColor = color ?? AppSurfaces.panelBackground(context);

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    return Material(
      color: panelColor,
      elevation: elevation,
      shadowColor:
          shadowColor ??
          Theme.of(context).colorScheme.shadow.withValues(alpha: 0.10),
      surfaceTintColor: Colors.transparent,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}
