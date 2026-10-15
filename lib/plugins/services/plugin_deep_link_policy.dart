import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/core/external_uri_router.dart';

/// מדיניות קישורי `otzaria://` בתוך WebView של תוסף.
///
/// הגבול היחיד הוא מחוות המשתמש — קישור שנלחץ מופעל, ניווט שסקריפט יזם נחסם.
/// אין כאן הרשאת מניפסט בכוונה: הקישור נכתב לא פעם בידי המשתמש עצמו בתוכן
/// שהוא שומר בתוסף, ולא בידי מחבר התוסף.
class PluginDeepLinkPolicy {
  /// פעולות שאינן מופעלות מקישור בתוך תוסף גם בלחיצת משתמש — כבדות או חושפות
  /// מידע מערכת, ואין להן שימוש לגיטימי בתוכן שמשתמש כותב.
  static bool isBlockedAction(ExternalUriAction action) =>
      action is ReindexLibraryAction ||
      action is ShowInfoAction ||
      action is InstallLocalPluginAction;

  /// האם הניווט נובע מלחיצת המשתמש על קישור.
  ///
  /// ב-Windows/macOS/iOS `LINK_ACTIVATED` נגזר מ-`IsUserInitiated` של המנוע;
  /// ב-Android השדה אינו מאוכלס ולכן נופלים ל-[NavigationAction.hasGesture].
  static bool isUserActivated(NavigationAction navigationAction) =>
      navigationAction.navigationType == NavigationType.LINK_ACTIVATED ||
      navigationAction.hasGesture == true;

  /// הכתובת שמותר לשגר בעקבות ניווט, או `null` אם לא הייתה מחוות משתמש.
  static Uri? dispatchUriForUserNavigation(
    Uri uri,
    NavigationAction navigationAction,
  ) {
    if (!isUserActivated(navigationAction)) return null;
    return resolveDispatchUri(uri);
  }

  /// הכתובת המנורמלת שיש לשגר, או `null` אם הקישור אינו מוכר או חסום.
  static Uri? resolveDispatchUri(Uri uri) {
    final normalized = ExternalUriRouter.normalizeUri(uri) ?? uri;
    final action = ExternalUriRouter.parseUri(normalized);
    if (action == null || isBlockedAction(action)) return null;
    return normalized;
  }
}
