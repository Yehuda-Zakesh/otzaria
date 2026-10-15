/// עיצוב inline משותף לכל הממירים — **מקור יחיד** לקו תחתי, קו חוצה,
/// צבע טקסט וסימון מרקר.
///
/// Word (OOXML), Word הבינארי, RTF ו-ODT מתארים את אותם עיצובים בשמות
/// שונים לגמרי, אך ה-HTML שהקורא מקבל חייב להיות זהה: פלט שנכתב פעמיים
/// נוטה להתפצל בין הממירים, ואז אותו מסמך נראה אחרת לפי הסיומת שלו.
library;

/// סוג הקו התחתי, אחרי נרמול מכל הפורמטים לערכי `text-decoration-style`
/// של CSS.
enum UnderlineKind {
  single,
  double,
  dotted,
  dashed,
  wavy;

  /// ערך `text-decoration-style`, או `null` לקו פשוט שאינו דורש `style`.
  String? get cssStyle => switch (this) {
    UnderlineKind.single => null,
    UnderlineKind.double => 'double',
    UnderlineKind.dotted => 'dotted',
    UnderlineKind.dashed => 'dashed',
    UnderlineKind.wavy => 'wavy',
  };
}

/// ממפה שם סוג-קו-תחתי של Word (`w:u w:val`) או של ODF
/// (`style:text-underline-style`) ל-[UnderlineKind].
///
/// שני התקנים משתמשים באותן מילים (`dash`, `dotted`, `wave`) עם סיומות
/// עוצמה משתנות (`Heavy`, `Long`, `DotDash`), ולכן ההתאמה היא לפי תחילית.
UnderlineKind underlineKindFromName(String? value) {
  final v = (value ?? '').toLowerCase();
  if (v.startsWith('wav')) return UnderlineKind.wavy;
  if (v.startsWith('dot')) return UnderlineKind.dotted;
  if (v.startsWith('dash')) return UnderlineKind.dashed;
  if (v == 'double') return UnderlineKind.double;
  return UnderlineKind.single;
}

/// עוטף טקסט בעיצוב קו תחתי.
///
/// קו פשוט ללא צבע ועובי מקבל `<u>` — תג קצר שניתן למזג בין runs סמוכים.
/// כל שאר הווריאנטים דורשים `text-decoration` מפורש.
({String open, String close}) underlineTags({
  UnderlineKind kind = UnderlineKind.single,
  String? color,
  bool thick = false,
  bool doubleLine = false,
}) {
  final effective = doubleLine && kind == UnderlineKind.single
      ? UnderlineKind.double
      : kind;
  final style = effective.cssStyle;
  final hasColor = color != null && color.isNotEmpty;
  if (style == null && !thick && !hasColor) {
    return (open: '<u>', close: '</u>');
  }
  final css = StringBuffer('text-decoration: underline');
  if (style != null) css.write(' $style');
  css.write(';');
  if (hasColor) css.write(' text-decoration-color: $color;');
  if (thick) css.write(' text-decoration-thickness: 200%;');
  return (open: '<span style="$css">', close: '</span>');
}

/// עוטף טקסט בקו חוצה. קו יחיד מקבל `<s>`; כפול דורש `text-decoration`.
({String open, String close}) strikeTags({bool doubleLine = false}) =>
    doubleLine
    ? (
        open: '<span style="text-decoration: line-through double;">',
        close: '</span>',
      )
    : (open: '<s>', close: '</s>');

/// עוטף טקסט בצבע. [color] כבר בפורמט CSS (`#RRGGBB` או שם צבע).
({String open, String close}) colorTags(String color) => (
  open: '<span style="color:$color">',
  close: '</span>',
);

/// עוטף טקסט בסימון מרקר.
({String open, String close}) highlightTags(String color) => (
  open: '<span style="background-color:$color">',
  close: '</span>',
);

/// 17 צבעי הפלטה של Word, לפי סדר האינדקס (`ico`).
///
/// אותה טבלה בדיוק משרתת שלושה מקומות: `sprmCIco`/`sprmCHighlight` ב-Word
/// הבינארי, `\highlightN` ב-RTF, ושמות ה-`w:highlight` ב-OOXML — שם הצבע
/// באינדקס N הוא בדיוק המילה ש-OOXML כותב.
const List<String> kWordColorPalette = [
  'auto',
  'black',
  'blue',
  'cyan',
  'green',
  'magenta',
  'red',
  'yellow',
  'white',
  'darkBlue',
  'darkCyan',
  'darkGreen',
  'darkMagenta',
  'darkRed',
  'darkYellow',
  'darkGray',
  'lightGray',
];

/// מסנן ערך צבע שהגיע מתוך המסמך.
///
/// מותרות רק הצורות שיש להן משמעות ב-CSS: `#RGB`/`#RRGGBB`/`#RRGGBBAA` או
/// שם צבע. ערך אחר אינו צבע אלא ניסיון להיחלץ מתוך ה-`style="…"` ולהזריק
/// תגיות משלו — ומשם הן מגיעות גם לתוכן העניינים ולאינדקס.
String? sanitizeCssColor(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  return _cssColorPattern.hasMatch(v) ? v : null;
}

final RegExp _cssColorPattern = RegExp(
  r'^(?:#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|[a-zA-Z]+)$',
);

/// כמו [sanitizeCssColor], ובנוסף מקבל את הצורות הפונקציונליות של CSS.
///
/// נפרד ממנו בכוונה: Word, ODF ו-RTF אינם מייצרים `rgb()` לעולם, ולכן אין
/// טעם להרחיב עבורם את שטח התקיפה. מסמך HTML **כן** כותב אותן, ומנוע התצוגה
/// מכיר אותן.
///
/// הפסיקים והסוגריים מאומתים במלואם: ערך שאינו תואם בדיוק לאחת הצורות נדחה,
/// ולכן אין דרך להחליק דרכו `url(...)` או תו שסוגר את המאפיין.
String? sanitizeCssColorValue(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  if (_cssColorPattern.hasMatch(v)) return v;
  return _cssColorFunctionPattern.hasMatch(v) ? v : null;
}

/// `rgb()`/`rgba()`/`hsl()`/`hsla()` עם 3–4 רכיבים מספריים (ואחוזים).
final RegExp _cssColorFunctionPattern = RegExp(
  r'^(?:rgba?|hsla?)\(\s*'
  r'-?[\d.]+%?\s*,\s*-?[\d.]+%?\s*,\s*-?[\d.]+%?'
  r'(?:\s*,\s*-?[\d.]+%?)?\s*\)$',
  caseSensitive: false,
);

/// ממפה יישור אנכי בתא לערך CSS. שני התקנים חולקים את רוב המילים, אך Word
/// כותב `center` ו-ODF כותב `middle` — ו-`center` אינו ערך חוקי ב-CSS.
String? cssVerticalAlign(String? value) => switch (value?.toLowerCase()) {
  'top' => 'top',
  'center' || 'middle' => 'middle',
  'bottom' => 'bottom',
  _ => null,
};

/// ממיר שם צבע של Word לערך CSS, או `null` כשאין לצייר צבע.
///
/// רוב השמות תקניים ב-CSS; `darkYellow` אינו קיים שם וממופה ל-HEX.
/// `auto`/`none` ו**שחור** מוחזרים כ-`null`: שחור מפורש שובר את המצב הכהה,
/// שכן הרקע שם כהה אף הוא.
String? cssColorForWordName(String? name, {bool allowBlack = false}) {
  final v = (name ?? '').toLowerCase();
  if (v.isEmpty || v == 'auto' || v == 'none') return null;
  if (!allowBlack && v == 'black') return null;
  if (v == 'darkyellow') return '#808000';
  return sanitizeCssColor(v);
}

/// ממיר אינדקס בפלטת Word לערך CSS. משמש את RTF ואת Word הבינארי.
String? cssColorForWordIndex(int? index, {bool allowBlack = false}) {
  if (index == null || index < 0 || index >= kWordColorPalette.length) {
    return null;
  }
  return cssColorForWordName(
    kWordColorPalette[index],
    allowBlack: allowBlack,
  );
}

/// ממיר ערך HEX של Word (`"C00000"`, ללא `#`) לצבע CSS, או `null` כשהוא
/// אוטומטי/שחור — ראו [cssColorForWordName].
String? cssColorForWordHex(String? hex) {
  final v = (hex ?? '').trim();
  if (v.isEmpty) return null;
  final lower = v.toLowerCase();
  if (lower == 'auto' || lower == '000000') return null;
  return sanitizeCssColor(v.startsWith('#') ? v : '#$v');
}
