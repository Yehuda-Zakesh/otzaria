import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_linux/flutter_inappwebview_linux.dart'
    show LinuxWebViewHostHandles, LinuxWebViewHostWindow;
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';

/// Linux: popups ודיאלוגים של WebView נפתחים בחלון שמציג אותו ולא בחלון הראשי.
/// רק השמת closure; ה-registry והחלונות נקראים כשנוצר WebView.
void installLinuxWebViewHostResolver([ViewWindowRegistry? registry]) {
  LinuxWebViewHostWindow.resolver = (viewId) =>
      linuxWebViewHostOf(registry ?? ViewWindowRegistry.instance, viewId);
}

/// ה-`GtkWindow*` וה-`FlView*` של חלון ה-Dart שמציג את [viewId]; null לתצוגה
/// הראשית ולמזהה לא מוכר, ואז התוסף משתמש בחלון הראשי.
@visibleForTesting
LinuxWebViewHostHandles? linuxWebViewHostOf(
  ViewWindowRegistry registry,
  int viewId,
) {
  for (final entry in registry.windows) {
    final handle = entry.handle;
    if (handle.view.viewId != viewId) continue;
    final window = handle.nativeHandle;
    final view = handle.flutterViewHandle;
    if (window == null || view == null) return null;
    return (windowHandle: window, flutterViewHandle: view);
  }
  return null;
}
