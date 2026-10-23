import 'dart:developer' show Timeline;
import 'dart:typed_data';

/// הסיבה ששורה נפלה ממסלול הספאנים של SmartTextWidget ל-HtmlWidget.
enum SmartTextFullPathReason {
  /// תג בלוק: div, p, רשימה, טבלה, ציטוט, pre, כותרת עם attributes או באמצע שורה.
  block,

  /// `<img>` / `<svg>`.
  image,

  /// `<sup>` / `<sub>` שנותרו אחרי processText (fwfh מממש אותם כ-WidgetSpan).
  supSub,

  /// attribute של `id` או `name` (עוגן ניווט של fwfh).
  anchorId,

  /// `style` עם תכונה שמסלול הספאנים אינו מתרגם (margin, line-height, px…).
  unsupportedStyle,

  /// תג inline שמסלול הספאנים אינו מכיר (font, code, q…).
  otherTag,

  /// מבנה: שורה שכולה `<br>`, או markup שאינו מתאים לאף סיבה אחרת.
  structure,

  /// RenderMode שאינו column — המסלול המהיר לא נוסה.
  nonColumnMode,
}

/// מוני רינדור מצטברים של SmartTextWidget לאבחון מפתחים.
///
/// כשהאיסוף כבוי כל נקודת מדידה חוזרת מיד אחרי בדיקת [enabled], בלי הקצאות.
class SmartTextRenderStats {
  SmartTextRenderStats._();

  /// האם לספור; מופעל על-ידי DeveloperDiagnostics או בדיקת ביצועים.
  static bool enabled = false;

  static int _fastInline = 0;
  static int _fastHeading = 0;
  static int _fullHtml = 0;
  static final Int32List _reasons = Int32List(
    SmartTextFullPathReason.values.length,
  );
  static int _processHits = 0;
  static int _processMisses = 0;
  static int _processUncachedMicros = 0;
  static int _fwfhBuilds = 0;
  static int _fwfhBuildMicros = 0;

  /// זמן התחלה למדידה, או 0 כשהאיסוף כבוי.
  static int startMicros() => enabled ? Timeline.now : 0;

  static void fastLine({required bool heading}) {
    if (!enabled) return;
    if (heading) {
      _fastHeading++;
    } else {
      _fastInline++;
    }
  }

  /// שורה ב-HtmlWidget; בלי [columnMode] המסלול המהיר לא נוסה כלל.
  static void fullLine({required bool columnMode}) {
    if (!enabled) return;
    _fullHtml++;
    if (!columnMode) _reasons[SmartTextFullPathReason.nonColumnMode.index]++;
  }

  /// מסווג ורושם שורה שהמסלול המהיר דחה; נקרא רק בהחטאת מטמון.
  static void fullPathHtml(String html) {
    if (!enabled) return;
    _reasons[classifyFullPath(html).index]++;
  }

  static void processTextHit() {
    if (enabled) _processHits++;
  }

  static void processTextMiss(int startMicros) {
    if (!enabled) return;
    _processMisses++;
    if (startMicros > 0) _processUncachedMicros += Timeline.now - startMicros;
  }

  static void fwfhBuild(int startMicros) {
    if (!enabled || startMicros == 0) return;
    _fwfhBuilds++;
    _fwfhBuildMicros += Timeline.now - startMicros;
  }

  /// מחזיר את המונים מאז הקריאה הקודמת ומאפס; null כשלא נספר דבר.
  static Map<String, Object?>? takeAndReset() {
    final lines = _fastInline + _fastHeading + _fullHtml;
    if (lines == 0 &&
        _processHits + _processMisses == 0 &&
        _fwfhBuilds == 0 &&
        !_reasons.any((count) => count > 0)) {
      return null;
    }
    final result = <String, Object?>{
      'fastInline': _fastInline,
      'fastHeading': _fastHeading,
      'fullHtml': _fullHtml,
      'fullReasons': {
        for (final reason in SmartTextFullPathReason.values)
          if (_reasons[reason.index] > 0) reason.name: _reasons[reason.index],
      },
      'processHits': _processHits,
      'processMisses': _processMisses,
      'processUncachedMs': _microsToMs(_processUncachedMicros),
      'fwfhBuilds': _fwfhBuilds,
      'fwfhBuildMs': _microsToMs(_fwfhBuildMicros),
    };
    reset();
    return result;
  }

  static void reset() {
    _fastInline = 0;
    _fastHeading = 0;
    _fullHtml = 0;
    _reasons.fillRange(0, _reasons.length, 0);
    _processHits = 0;
    _processMisses = 0;
    _processUncachedMicros = 0;
    _fwfhBuilds = 0;
    _fwfhBuildMicros = 0;
  }

  static double _microsToMs(int micros) => (micros / 100).round() / 10;

  static final RegExp _tagRegex = RegExp(
    r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>',
  );
  static final RegExp _idRegex = RegExp(r'(^|\s)(id|name)\s*=');
  static const Set<String> _inlineTags = {
    'span',
    'a',
    'b',
    'strong',
    'i',
    'em',
    'cite',
    'dfn',
    'var',
    'u',
    'ins',
    's',
    'strike',
    'del',
    'mark',
    'big',
    'small',
    'br',
  };
  static const Set<String> _blockTags = {
    'div',
    'p',
    'ul',
    'ol',
    'li',
    'table',
    'tr',
    'td',
    'th',
    'blockquote',
    'pre',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
    'details',
    'center',
  };

  /// הסיבה לנפילה של [html] שמסלול הספאנים דחה; תג מבני גובר על עיצוב.
  /// משקף את כללי `InlineHtmlDocument` בקירוב, לאבחון בלבד.
  static SmartTextFullPathReason classifyFullPath(String html) {
    SmartTextFullPathReason? weaker;
    for (final match in _tagRegex.allMatches(html)) {
      if (match[1] == '/') continue;
      final name = match[2]!.toLowerCase();
      final attributes = match[3]!;
      if (_blockTags.contains(name)) return SmartTextFullPathReason.block;
      if (name == 'img' || name == 'svg') return SmartTextFullPathReason.image;
      if (name == 'sup' || name == 'sub') return SmartTextFullPathReason.supSub;
      if (_idRegex.hasMatch(attributes)) {
        return SmartTextFullPathReason.anchorId;
      }
      if (!_inlineTags.contains(name)) {
        weaker ??= SmartTextFullPathReason.otherTag;
      } else if (attributes.contains('style=')) {
        weaker ??= SmartTextFullPathReason.unsupportedStyle;
      }
    }
    return weaker ?? SmartTextFullPathReason.structure;
  }
}
