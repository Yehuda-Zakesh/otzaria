/// רשימת ההיתר של CSS שמנוע התצוגה של אוצריא מכיר — **מקור יחיד**.
///
/// שכבת התצוגה מקבלת את ה-HTML של הספר כמות שהוא ומגישה אותו ל-`HtmlWidget`,
/// ולכן כל תכונה שהמנוע מכיר אמורה לשרוד את ההמרה. מנגד, ערך שמגיע מתוך מסמך
/// שהמשתמש הוריד מהאינטרנט אינו אמור להגיע לגוף הספר בלי אימות: ערך שמכיל
/// גרש נחלץ מה-`style="…"` ומזריק תגיות משלו — ומשם הן מגיעות גם לתוכן
/// העניינים ולאינדקס.
///
/// לכן הסינון כאן הוא **רשימת היתר כפולה**: שם התכונה חייב להופיע ב-
/// [_validators], והערך חייב לעבור את המאמת של אותה תכונה בדיוק. תכונה
/// שאינה ברשימה נעלמת מאליה — כולל `position`, `transform`, `float`,
/// `opacity`, `border-radius`, `animation` ו-`text-emphasis`, שאינם נתמכים
/// בקורא בלאו הכי.
library;

import 'package:otzaria/utils/text/inline_style.dart';

/// מאמת ערך של תכונה. מחזיר את הערך לכתיבה (אפשר מנורמל), או `null` לדחייה.
typedef CssValueValidator = String? Function(String value);

/// מסנן הצהרות CSS ומחזיר ערך `style` לכתיבה, או `null` כשלא שרדה אף הצהרה.
///
/// [skip] הן תכונות שהקורא כבר תרגם לתגית (למשל `font-weight: bold` שהפך
/// ל-`<b>`) — כתיבתן שוב הייתה מכפילה את אותו עיצוב.
/// [blockOnly] פותח את התכונות שיש להן משמעות רק על תג בלוק.
String? cssStyleFrom(
  Map<String, String> declarations, {
  Set<String> skip = const {},
  bool blockOnly = false,
}) {
  if (declarations.isEmpty) return null;
  final kept = <String>[];
  for (final entry in declarations.entries) {
    final property = entry.key;
    if (skip.contains(property)) continue;
    if (!blockOnly && _blockOnlyProperties.contains(property)) continue;
    final validator = _validators[property];
    if (validator == null) continue;
    final value = validator(entry.value);
    if (value == null || value.isEmpty) continue;
    kept.add('$property: $value');
  }
  return kept.isEmpty ? null : kept.join('; ');
}

/// תכונות שאין להן משמעות על תג inline. `text-align` על `<span>` אינו עובד
/// בקורא, ו-`direction` לבדה על `<span>` אינה עושה דבר בלי `inline-block`.
const Set<String> _blockOnlyProperties = {'text-align'};

// ── מאמתים ────────────────────────────────────────────────────────────────

/// מידה: מספר עם יחידה נתמכת, או `0` חשוף.
///
/// `rem` **אינה** ברשימה — הקורא מתעלם ממנה, ולכן ערך כזה נדחה כאן ולא
/// נכתב לגוף הספר כהצהרה מתה.
final RegExp _length = RegExp(
  r'^-?(?:\d+(?:\.\d+)?|\.\d+)(?:px|pt|em|%)?$',
  caseSensitive: false,
);

final RegExp _positiveInteger = RegExp(r'^\d{1,4}$');

/// שם גופן חשוף — מילה אחת בלבד, בלי רווחים.
final RegExp _bareFontName = RegExp(r'^[a-zA-Z][a-zA-Z0-9-]*$');

/// שם גופן במרכאות. מותרים אותיות, ספרות, רווח, מקף ונקודה — ובעברית.
final RegExp _quotedFontName = RegExp(
  r"^[\w֐-׿][\w֐-׿ .-]*$",
);

/// מילת מפתח של CSS — חסרת רגישות לרישיות. הערך מוחזר מנורמל, כדי שהפלט
/// יהיה זהה בין `NOWRAP` ל-`nowrap`.
String? _keyword(String value, Set<String> allowed) {
  final normalized = value.toLowerCase();
  return allowed.contains(normalized) ? normalized : null;
}

String? _lengthValue(String value) => _length.hasMatch(value) ? value : null;

/// 1–4 מידות מופרדות ברווח — הצורה המקוצרת של `padding`/`margin`/`border-width`.
String? _lengthShorthand(String value) {
  final parts = value.split(_whitespace).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || parts.length > 4) return null;
  for (final part in parts) {
    if (!_length.hasMatch(part)) return null;
  }
  return parts.join(' ');
}

final RegExp _whitespace = RegExp(r'\s+');

/// `font-weight`. `bolder`/`lighter` נדחים — הקורא אינו מכיר אותם.
String? _fontWeight(String value) {
  final normalized = value.toLowerCase();
  if (normalized == 'bold' || normalized == 'normal') return normalized;
  final weight = int.tryParse(normalized);
  if (weight == null || weight < 100 || weight > 900) return null;
  return weight % 100 == 0 ? normalized : null;
}

/// `font-style`. `oblique` נדחה — הקורא אינו מכיר אותו.
String? _fontStyle(String value) => _keyword(value, {'italic', 'normal'});

const Set<String> _fontSizeKeywords = {
  'xx-small',
  'x-small',
  'small',
  'medium',
  'large',
  'x-large',
  'xx-large',
  'larger',
  'smaller',
};

String? _fontSize(String value) =>
    _keyword(value, _fontSizeKeywords) ?? _lengthValue(value);

const Set<String> _genericFontFamilies = {
  'serif',
  'sans-serif',
  'monospace',
  'cursive',
  'fantasy',
};

/// רשימת גופנים. שם מרובה-מילים חייב להיות במרכאות — בלעדיהן הקורא קורא רק
/// את המילה הראשונה. הפלט נכתב מחדש עם מרכאות בודדות, כדי שגרש כפול מתוך
/// המסמך לא ייכנס אל תוך `style="…"`.
String? _fontFamily(String value) {
  final names = <String>[];
  for (final raw in value.split(',')) {
    final item = raw.trim();
    if (item.isEmpty) continue;
    final unquoted = _unquote(item);
    if (unquoted == null) return null;
    if (_genericFontFamilies.contains(unquoted.toLowerCase()) ||
        _bareFontName.hasMatch(unquoted)) {
      names.add(unquoted);
      continue;
    }
    if (!_quotedFontName.hasMatch(unquoted)) return null;
    names.add("'$unquoted'");
  }
  return names.isEmpty ? null : names.join(', ');
}

/// מסיר מרכאות עוטפות. מחזיר `null` כשהמרכאות אינן מאוזנות או שיש מרכאות
/// בפנים — שתיהן דרכים להיחלץ מהמאפיין.
String? _unquote(String item) {
  for (final quote in const ['"', "'"]) {
    if (item.length >= 2 && item.startsWith(quote) && item.endsWith(quote)) {
      final inner = item.substring(1, item.length - 1);
      return inner.contains(quote) ? null : inner;
    }
  }
  return (item.contains('"') || item.contains("'")) ? null : item;
}

String? _lineHeight(String value) =>
    _keyword(value, {'normal'}) ?? _lengthValue(value);

String? _textAlign(String value) =>
    _keyword(value, {'left', 'right', 'center', 'justify', 'start', 'end'});

String? _verticalAlign(String value) => _keyword(value, {
  'super',
  'sub',
  'top',
  'bottom',
  'middle',
  'baseline',
});

String? _whiteSpace(String value) =>
    _keyword(value, {'nowrap', 'normal', 'pre', 'pre-wrap', 'pre-line'});

/// `direction`. רק `ltr` — הקורא כולו RTL, ולכן `rtl` הוא no-op שמנפח כל שורה.
String? _direction(String value) => _keyword(value, {'ltr'});

/// `display`. `none` **אינו** ברשימה בכוונה: אלמנט מוסתר מדולג כליל בכל
/// הפורמטים, ולכן הוא לעולם אינו מגיע לכאן.
String? _display(String value) =>
    _keyword(value, {'inline-block', 'inline', 'block'});

const Set<String> _lineStyles = {
  'solid',
  'double',
  'dotted',
  'dashed',
  'wavy',
};

const Set<String> _borderStyles = {
  'solid',
  'double',
  'dotted',
  'dashed',
  'groove',
  'ridge',
  'inset',
  'outset',
  'none',
  'hidden',
};

const Set<String> _decorationLines = {
  'underline',
  'overline',
  'line-through',
  'none',
};

/// `text-decoration` בצורתו המקוצרת: קווים, סוג קו וצבע בכל סדר.
String? _textDecoration(String value) {
  final parts = value
      .toLowerCase()
      .split(_whitespace)
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 4) return null;
  var lines = 0;
  var styles = 0;
  var colors = 0;
  for (final part in parts) {
    if (_decorationLines.contains(part)) {
      lines++;
    } else if (_lineStyles.contains(part)) {
      styles++;
    } else if (sanitizeCssColorValue(part) != null) {
      colors++;
    } else {
      return null;
    }
  }
  if (lines == 0 || styles > 1 || colors > 1) return null;
  return parts.join(' ');
}

String? _decorationStyle(String value) => _keyword(value, _lineStyles);

/// `text-decoration-thickness`. **באחוזים בלבד** — הקורא מתעלם מפיקסלים,
/// וכתיבתם הייתה מצהירה על עובי שאינו מצויר.
String? _decorationThickness(String value) =>
    value.endsWith('%') && _length.hasMatch(value) ? value : null;

/// `border` בצורתו המקוצרת: עובי, סוג וצבע בכל סדר.
String? _border(String value) {
  final parts = value
      .toLowerCase()
      .split(_whitespace)
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 3) return null;
  var widths = 0;
  var styles = 0;
  var colors = 0;
  for (final part in parts) {
    if (_borderStyles.contains(part)) {
      styles++;
    } else if (_length.hasMatch(part)) {
      widths++;
    } else if (sanitizeCssColorValue(part) != null) {
      colors++;
    } else {
      return null;
    }
  }
  if (widths > 1 || styles > 1 || colors > 1) return null;
  return parts.join(' ');
}

String? _borderStyle(String value) => _keyword(value, _borderStyles);

/// `text-shadow`. הקורא מצייר צל של 2–4 רכיבים; צל עם חמישה ומעלה מבטל את
/// **כל** התכונה, ולכן ערך כזה נדחה כאן ואינו נכתב.
String? _textShadow(String value) {
  final shadows = <String>[];
  for (final raw in value.toLowerCase().split(',')) {
    final parts = raw.split(_whitespace).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2 || parts.length > 4) return null;
    var lengths = 0;
    var colors = 0;
    for (final part in parts) {
      if (_length.hasMatch(part)) {
        lengths++;
      } else if (sanitizeCssColorValue(part) != null) {
        colors++;
      } else {
        return null;
      }
    }
    if (lengths < 2 || lengths > 3 || colors > 1) return null;
    shadows.add(parts.join(' '));
  }
  return shadows.isEmpty ? null : shadows.join(', ');
}

const Set<String> _listStyleTypes = {
  'disc',
  'circle',
  'square',
  'none',
  'decimal',
  'decimal-leading-zero',
  'lower-alpha',
  'upper-alpha',
  'lower-latin',
  'upper-latin',
  'lower-roman',
  'upper-roman',
  'lower-greek',
  'hebrew',
};

String? _listStyleType(String value) => _keyword(value, _listStyleTypes);

String? _colorValue(String value) => sanitizeCssColorValue(value);

/// צבע טקסט. **שחור מפורש נדחה** — לאוצריא יש מצב יום ומצב לילה, וצבע
/// שנקבע ידנית אינו משתנה ביניהם; טקסט שחור נעלם ברקע כהה. זהו אותו כלל
/// שחל בכל שאר הפורמטים, וכאן הוא יושב במקום אחד כדי שיחול גם על תגית
/// inline וגם על בלוק ועל תא בטבלה.
String? _textColor(String value) {
  final color = sanitizeCssColorValue(value);
  if (color == null) return null;
  return _isBlack(color) ? null : color;
}

/// `background` מקוצר — מתקבל **רק** כשהוא צבע. כל שאר הצורות מביאות משאב
/// (`url(...)`), ומשאב חיצוני אינו נטען בהמרה ולא בקורא.
///
/// **רקע לבן נדחה** מאותה סיבה הפוכה: הוא ברירת המחדל ושובר את המצב הכהה.
/// רקע שחור דווקא נשמר — הוא בחירה מכוונת של המחבר.
String? _backgroundColor(String value) {
  final color = sanitizeCssColorValue(value);
  if (color == null) return null;
  return _isWhite(color) ? null : color;
}

bool _isBlack(String color) {
  final v = color.toLowerCase();
  return v == 'black' || v == '#000' || v == '#000000';
}

bool _isWhite(String color) {
  final v = color.toLowerCase();
  return v == 'white' || v == '#fff' || v == '#ffffff';
}

/// שם התכונה → המאמת שלה. זו רשימת ההיתר; כל מה שאינו כאן נעלם.
final Map<String, CssValueValidator> _validators = {
  'color': _textColor,
  'background-color': _backgroundColor,
  'background': _backgroundColor,
  'font-weight': _fontWeight,
  'font-style': _fontStyle,
  'font-size': _fontSize,
  'font-family': _fontFamily,
  'line-height': _lineHeight,
  'text-align': _textAlign,
  'vertical-align': _verticalAlign,
  'white-space': _whiteSpace,
  'direction': _direction,
  'display': _display,
  'text-decoration': _textDecoration,
  'text-decoration-line': _textDecoration,
  'text-decoration-style': _decorationStyle,
  'text-decoration-color': _colorValue,
  'text-decoration-thickness': _decorationThickness,
  'text-shadow': _textShadow,
  'list-style-type': _listStyleType,
  'border': _border,
  'border-top': _border,
  'border-right': _border,
  'border-bottom': _border,
  'border-left': _border,
  'border-style': _borderStyle,
  'border-width': _lengthShorthand,
  'border-color': _colorValue,
  'padding': _lengthShorthand,
  'padding-top': _lengthValue,
  'padding-right': _lengthValue,
  'padding-bottom': _lengthValue,
  'padding-left': _lengthValue,
  'margin': _lengthShorthand,
  'margin-top': _lengthValue,
  'margin-right': _lengthValue,
  'margin-bottom': _lengthValue,
  'margin-left': _lengthValue,
  'width': _lengthValue,
  'height': _lengthValue,
};

/// ערך מספרי חיובי למאפיין מבני (`width`/`colspan`/`border`) — לא CSS.
String? positiveIntegerAttribute(String? value) {
  final v = value?.trim();
  if (v == null || !_positiveInteger.hasMatch(v)) return null;
  return int.parse(v) > 0 ? v : null;
}
