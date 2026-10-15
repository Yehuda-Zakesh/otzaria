/// צורת ההשוואה של שמות ספרים וכינויים באיתור מקורות, מעל [normalizeForFindRefMatch].
///
/// חלה רק בהחלטה אם יש התאמה; התוצאה נושאת את הצורה הרגילה, כי בחיפוש הכותרות
/// הפנימיות "דיינים" אינו "דינים". כינויים מושווים ב-[bookNameSpellingForm] בלבד.
library;

/// ראשי-תיבות שה"א הידיעה באה לפניהם ("הרמב"ם"), כפי שהכריע מחקר השמות של הספרייה.
/// רשימת היתר ולא דגם: רש"י, חז"ל, שו"ת ושו"ע אינם מקבלים ה"א.
const Set<String> sagesTakingDefiniteArticle = {
  // ראשונים
  'רמבם', 'רמבן', 'ראש', 'רשבא', 'רשבם', 'ריטבא', 'רדק', 'רלבג', 'ריף',
  'ראבד', 'ראבע', 'רן', 'רש', 'רי', 'רסג', 'ראה', 'ריבא', 'ריד', 'רדבז',
  'רמה', 'רמך', 'רזה', 'ריאז', 'ריץ',
  // אחרונים ומקובלים
  'רמא', 'טז', 'שך', 'בח', 'סמע', 'רעב', 'מביט', 'חידא', 'יעבץ', 'תשבץ',
  'מלבים', 'רמק', 'רמחל', 'רשש', 'רידבז', 'אדרת', 'נציב', 'רדל', 'רימ',
  'ראיה', 'ארי', 'אריזל', 'מב', 'רשז',
  // מהר"X
  'מהרם', 'מהרל', 'מהרי', 'מהרץ', 'מהרש', 'מהרשא', 'מהרשל', 'מהרשך',
  'מהרשם', 'מהריל', 'מהריק', 'מהריט', 'מהרחו', 'מהראל', 'מהרזו', 'מהריו',
  // הג"ר
  'גרא', 'גרעא', 'גרח', 'גרשז', 'גריז', 'גרישא', 'גרשש', 'גריד', 'גראל',
  'גרש', 'גרנט', 'גרמפ', 'גריב', 'גרמ', 'גריש', 'גרעקא', 'גרשזא',
  // הקורפוס
  'שס', 'תנך', 'נך', 'קבה',
};

/// וו/יי כפולות כיחידה — כתיב מלא וחסר (מקוואות/מקואות).
String bookNameSpellingForm(String text) =>
    text.contains('וו') || text.contains('יי')
    ? text.replaceAll('וו', 'ו').replaceAll('יי', 'י')
    : text;

/// טוקן אחד בצורת ההשוואה: [bookNameSpellingForm], ובלי ה"א הידיעה שלפני
/// ראשי-תיבות מ-[sagesTakingDefiniteArticle].
String bookNameMatchToken(String token) {
  final t = bookNameSpellingForm(token);
  if (t.length > 2 &&
      t.codeUnitAt(0) == 0x05D4 &&
      sagesTakingDefiniteArticle.contains(t.substring(1))) {
    return t.substring(1);
  }
  return t;
}

/// [text] כבר מנורמל ומופרד ברווחים יחידים. לשאילתות ולכותרות — לא לכינויים: כינוי
/// שגוי "הרמב"ם הלכות X" על מפרש היה נעשה זהה ל"רמב"ם הלכות X" של משנה תורה.
String bookNameMatchForm(String text) {
  if (!text.contains('וו') && !text.contains('יי') && !text.contains('ה')) {
    return text;
  }
  return text.split(' ').map(bookNameMatchToken).join(' ');
}

/// מילות השאילתה שנכתבו בגרשיים ("רמב"ם"), בצורתן המנורמלת. ספר שגם אצלו
/// המילה כתובה כך מועדף בשוויון — הנרמול לבדו אינו מבחין בגרשיים.
Set<String> quotedWordsOf(String raw, String Function(String) normalize) {
  final out = <String>{};
  var start = 0;
  for (var i = 0; i <= raw.length; i++) {
    if (i < raw.length && !_isWordSeparator(raw.codeUnitAt(i))) continue;
    if (_hasInnerQuote(raw, start, i)) {
      final n = normalize(raw.substring(start, i));
      if (n.isNotEmpty && !n.contains(' ')) out.add(n);
    }
    start = i + 1;
  }
  return out;
}

bool _hasInnerQuote(String text, int start, int end) {
  for (var i = start + 1; i < end - 1; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x22 || c == 0x27 || c == 0x05F3 || c == 0x05F4) return true;
  }
  return false;
}

/// `[\s,.:;()\[\]־-]` של RegExp, בלי לפצל כל כינוי בטעינה.
bool _isWordSeparator(int c) => switch (c) {
  0x09 || 0x0A || 0x0B || 0x0C || 0x0D || 0x20 => true,
  0x2C || 0x2E || 0x3A || 0x3B || 0x28 || 0x29 || 0x5B || 0x5D => true,
  0x2D || 0x05BE || 0xA0 || 0x1680 || 0x2028 || 0x2029 || 0x202F => true,
  0x205F || 0x3000 || 0xFEFF => true,
  _ => c >= 0x2000 && c <= 0x200A,
};
