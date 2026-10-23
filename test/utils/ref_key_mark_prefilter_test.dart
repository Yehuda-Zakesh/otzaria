import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

// אורקל: refKeyTokens כפי שהיה לפני הסינון המוקדם, מועתק כלשונו.
final RegExp _oracleRange = RegExp(
  '''(?:^|[\\s,.:])(?:\\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)[.:]?\\s*([-–־])\\s*'''
  '''(?:\\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)[.:]?\\s*\$''',
);
final RegExp _oracleAmudA = RegExp('''(?<![א-ת])ע["'״׳]א(?![א-ת])''');
final RegExp _oracleAmudB = RegExp('''(?<![א-ת])ע["'״׳]ב(?![א-ת])''');
const _oracleLocators = {
  'פרק', 'פסוק', 'פסקה', 'סעיף', 'סימן', 'הלכה', //
  'משנה', 'מאמר', 'דף', 'עמוד', 'אות',
};

List<String> _oracleTokens(String ref) {
  final range = _oracleRange.firstMatch(ref);
  final dash = range == null ? -1 : ref.indexOf(RegExp('[-–־]'), range.start);
  final head = dash > 0 ? ref.substring(0, dash) : ref;
  final daf = head
      .replaceAllMapped(
        RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=[,\s]|$)'''),
        (m) => '${m[1]} א',
      )
      .replaceAllMapped(
        RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=[,\s]|$)'''),
        (m) => '${m[1]} ב',
      );
  var cleaned = removeTeamim(removeVolwels(daf));
  cleaned = cleaned.replaceAll(_oracleAmudA, 'א').replaceAll(_oracleAmudB, 'ב');
  cleaned = cleaned
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9֐-׿\s]'), ' ').toLowerCase();
  return cleaned
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_oracleLocators.contains(t))
      .toList();
}

void main() {
  test('הפניה בלי מקף, נקודה או נקודתיים אינה נסרקת לטווח ולסימן דף', () {
    expect(mayHaveRangeOrDafMark('משנה ברורה, סימן א,  ב'), isFalse);
    expect(mayHaveRangeOrDafMark('בראשית א, ב'), isFalse);
    for (final ref in ['לב יא-יג', 'יח, י, ב–ג', 'מגדל־עז', 'ברכות ב.', 'ב:']) {
      expect(mayHaveRangeOrDafMark(ref), isTrue, reason: ref);
    }
  });

  test('הטוקנים זהים למימוש הקודם', () {
    final fixtures =
        jsonDecode(
              File('test/fixtures/ref_key_fixtures.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final inputs = <String>[
      for (final group in fixtures.values)
        for (final entry in group as List)
          for (final value in [
            (entry as Map)['input'],
            entry['heRef'],
            ...?entry['aliases'] as List?,
          ])
            if (value is String) value,
      'משנה ברורה, הקדמה,  א',
      'שולחן ערוך, אורח חיים, שט, ג',
      'ברכות, ב., א',
      'ברכות ב:-ג.',
      'תהלים ע"א',
      'ברכות ב ע"א',
      'בְּרֵאשִׁ֖ית א, ב',
      'רמב״ן על דברים,  ז, ט, א',
      'Genesis 1:1-3',
      '',
    ];
    for (final ref in inputs) {
      expect(refKeyTokens(ref), _oracleTokens(ref), reason: ref);
    }
  });
}
