/// פורמטי המספור של Word — שם `w:numFmt` של OOXML, קוד MSONFC של הפורמטים
/// הבינאריים, והמרת מספר לתצוגה.
///
/// מקור יחיד לשלושת הממירים: DOCX (רשימות והערות שוליים), WordML 2003
/// (`w:nfc`) ו-DOC בינארי (`sprmSNfcFtnRef`).
library;

import 'package:otzaria/utils/text/numeral_formats.dart';

/// ממיר מספר לתצוגה לפי [numFmt] (שם `w:numFmt` של OOXML).
///
/// פורמט שאינו מוכר נופל לספרות — כך שסימון תמיד נראה, גם במסמך עם פורמט
/// אקזוטי (יפני, קוריאני) שאין לו ייצוג עברי.
String formatWordNumber(int n, String numFmt) {
  switch (numFmt) {
    case 'decimalZero':
      return n < 10 ? '0$n' : '$n';
    case 'lowerLetter':
      return toLatinLetters(n, upper: false);
    case 'upperLetter':
      return toLatinLetters(n, upper: true);
    case 'lowerRoman':
      return toRomanNumeral(n).toLowerCase();
    case 'upperRoman':
      return toRomanNumeral(n);
    case 'hebrew1':
    case 'hebrew2':
      return toHebrewNumeral(n);
    case 'chicago':
      return _chicagoSymbol(n);
    case 'none':
      return '';
    case 'decimal':
    default:
      return '$n';
  }
}

/// סדרת הסימנים של Word בפורמט `chicago`: *, †, ‡, § ואחר כך כפולים.
String _chicagoSymbol(int n) {
  if (n < 1) return '';
  const symbols = ['*', '†', '‡', '§'];
  final index = (n - 1) % symbols.length;
  final repeat = (n - 1) ~/ symbols.length + 1;
  return symbols[index] * repeat;
}

/// קוד MSONFC → שם `w:numFmt`, כדי שמנוע המספור יישאר אחד.
///
/// 45 ו-47 הם שני פורמטי האותיות העבריות (`msonfcHebrew1`/`msonfcHebrew2`);
/// 46 ו-48 שביניהם הם ערביים, ולכן הרשימה אינה רצף.
String wordNumFmtForMsonfc(int? code) => switch (code) {
  0 => 'decimal',
  1 => 'upperRoman',
  2 => 'lowerRoman',
  3 => 'upperLetter',
  4 => 'lowerLetter',
  9 => 'chicago',
  22 => 'decimalZero',
  23 => 'bullet',
  45 || 47 => 'hebrew1',
  255 => 'none',
  _ => 'decimal',
};
