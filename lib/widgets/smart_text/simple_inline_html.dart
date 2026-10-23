import 'package:flutter/widgets.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';

/// יחסי הגדלים של fwfh ל-`<small>`/`<sup>` ול-`<big>`.
/// זהים בשלושת מסלולי הרינדור כדי ששורות שכנות לא ישנו את גודל הסוגריים.
const double kHtmlSmallerFontScale = 5 / 6;
const double kHtmlLargerFontScale = 6 / 5;

/// ממיר שורת HTML שאינה תלויה בהקשר (בלי קישורים וצבעי ערכת נושא) ל-[TextSpan].
/// markup אחר מחזיר null; ההמרה עצמה ב-[InlineHtmlDocument].
class SimpleInlineHtml {
  SimpleInlineHtml._();

  /// מנסה להמיר את [html]. מחזיר null כשנדרש HtmlWidget או הקשר (קישור).
  ///
  /// התוצאה נשמרת ב-LRU של [InlineHtmlDocument.parseLine].
  static TextSpan? tryParse(String html, TextStyle baseStyle) {
    final line = InlineHtmlDocument.parseLine(html, baseStyle);
    if (line == null || line.isHeading) return null;
    return line.document.staticSpan;
  }

  /// כותרת שהיא כל השורה (`<hN>` בלי attributes): fwfh מציג אותה כבלוק יחיד
  /// שהשוליים שלו נחתכים בקצות הגוף, ולכן היא טקסט אחד בסגנון [SimpleHeading.style].
  static SimpleHeading? tryParseHeading(String html, TextStyle baseStyle) {
    final line = InlineHtmlDocument.parseLine(html, baseStyle);
    if (line == null || !line.isHeading) return null;
    final span = line.document.staticSpan;
    if (span == null) return null;
    return SimpleHeading(line.style, span);
  }

  static final RegExp _wholeLineHeadingRegex = RegExp(
    r'^[\t\n\f\r ]*<h([1-6])>(.*)</h\1>[\t\n\f\r ]*$',
    dotAll: true,
  );

  static final RegExp _headingTagRegex = RegExp(r'</?h[1-6]\b');

  /// גודל ברירת המחדל של fwfh לכל רמת כותרת, ביחס לגופן הסובב.
  static const Map<String, double> _defaultHeadingScale = {
    'h1': 2,
    'h2': 1.5,
    'h3': 1.17,
    'h4': 1,
    'h5': 0.83,
    'h6': 0.67,
  };

  /// הסגנון שבו fwfh מציג שורה שכולה כותרת, או null כשהשורה אינה כותרת.
  static TextStyle? headingStyle(String html, TextStyle baseStyle) {
    if (!html.contains('<h')) return null;
    final match = _wholeLineHeadingRegex.firstMatch(html);
    if (match == null) return null;
    final content = match[2]!;
    for (
      var tagStart = content.indexOf('<');
      tagStart != -1;
      tagStart = content.indexOf('<', tagStart + 1)
    ) {
      if (_headingTagRegex.matchAsPrefix(content, tagStart) != null) {
        return null;
      }
    }
    return headingStyleForTag('h${match[1]}', baseStyle);
  }

  /// הסגנון של כותרת [tag] (`h1`-`h6`) שכל השורה בתוכה.
  static TextStyle? headingStyleForTag(String tag, TextStyle baseStyle) {
    final defaultScale = _defaultHeadingScale[tag];
    if (defaultScale == null) return null;
    final fontFamily = baseStyle.fontFamily;
    final sizeOverride = AppFonts.headingFontSizeOverride(tag, fontFamily);
    final scale = sizeOverride == null
        ? defaultScale
        : double.tryParse(sizeOverride.replaceFirst('em', ''));
    if (scale == null) return null;
    final weightOverride = AppFonts.headingFontWeightOverride(tag, fontFamily);
    final weight = weightOverride == null
        ? FontWeight.bold
        : FontWeight.values.firstWhere(
            (w) => w.value == int.tryParse(weightOverride),
            orElse: () => FontWeight.bold,
          );
    return baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 14.0) * scale,
      fontWeight: weight,
      fontVariations:
          baseStyle.fontVariations ??
          AppFonts.boldFontVariations(fontFamily, weight),
    );
  }
}

/// שורת כותרת שלמה: [span] מוצג ב-[style] של רמת הכותרת.
class SimpleHeading {
  final TextStyle style;
  final TextSpan span;

  const SimpleHeading(this.style, this.span);
}
