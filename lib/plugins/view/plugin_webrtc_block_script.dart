import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// חיבור WebRTC פונה לשרתי STUN/TURN בלי לעבור ב-CSP, בחוקי החסימה או ב-
// shouldInterceptRequest — ודרכו תוסף היה שולח נתונים לכל שרת. בלי הבנאים
// אין דרך לפתוח חיבור כזה. non-configurable כדי שהדף לא יגדיר אותם מחדש.
const String _webRtcBlockJs = r'''
(function () {
  ['RTCPeerConnection', 'webkitRTCPeerConnection'].forEach(function (name) {
    try {
      Object.defineProperty(window, name, {
        value: undefined,
        writable: false,
        configurable: false,
      });
    } catch (e) {}
  });
})();
''';

/// סקריפט שמסיר את WebRTC מ-WebView של תוסף.
///
/// מוזרק לכל frame — אחרת iframe ריק שהתוסף יוצר מחזיר לו את הבנאי.
UserScript buildPluginWebRtcBlockScript() {
  return UserScript(
    source: _webRtcBlockJs,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
  );
}
