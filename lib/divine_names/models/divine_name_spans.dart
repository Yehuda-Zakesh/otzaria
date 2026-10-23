import 'package:flutter/foundation.dart';

/// ערכי `kind` של מופע שם במסד (ארוזים ב-`span`, ר' [decodeDivineNameSpan]).
abstract final class DivineNameKind {
  static const int hvyh = 1;
  static const int adnut = 2;
  static const int el = 3;
  static const int eloah = 4;
  static const int elohim = 5;
  static const int ehyeh = 6;
  static const int shaddai = 7;
  static const int tzevaot = 8;
  static const int yah = 9;
}

/// מופע שם אחד בשורה: [start, end) באופסט תווים גלויים של השורה השמורה, בלי
/// גופי ההערות (`link_anchor` נמדד על השורה המלאה, איתם).
typedef DivineNameSpan = ({int start, int end, int kind});

/// פענוח `span` של `line_divine_name` ו-`line_note_divine_name`:
/// אורך << 7 | מקור << 4 | סוג (DivineSpanCode ב-SeforimLibrary).
/// מבנה פגום — FormatException; סוג/מקור לא מוכרים (10–15/5–7) עוברים כמות שהם.
({int end, int kind}) decodeDivineNameSpan(int start, int span) {
  final length = span >> 7;
  if (start < 0 ||
      span < 0 ||
      span > _maxInt32 ||
      length < 1 ||
      start + length > _maxInt32 ||
      ((span >> 4) & 0x7) == 0 ||
      (span & 0xF) == 0) {
    throw FormatException('divine-name span $span at $start is malformed');
  }
  return (end: start + length, kind: span & 0xF);
}

const int _maxInt32 = 0x7FFFFFFF;

/// ערך שאינו נכנס ב-Int32 היה נעטף בשקט באחסון הדחוס.
void _requireInt32(int value) {
  if (value != value.toSigned(32)) {
    throw FormatException('divine-name value $value exceeds Int32');
  }
}

/// מופעי השמות של ספר שלם, בצורה דחוסה: שורות ממוינות, ולכל שורה טווח
/// במערך שלשות (start, end, kind). עובר ל-isolate וחזרה בלי המרה.
@immutable
class DivineNameSpans {
  const DivineNameSpans._(this._lines, this._lineStarts, this._data);

  /// ספר בלי שמות מסומנים — גם מסד ישן בלי הטבלה.
  static final DivineNameSpans empty = DivineNameSpans._(
    Int32List(0),
    Int32List(1),
    Int32List(0),
  );

  final Int32List _lines;
  final Int32List _lineStarts;
  final Int32List _data;

  bool get isEmpty => _lines.isEmpty;

  /// מספר המופעים בכל הספר.
  int get length => _data.length ~/ 3;

  /// המופעים בשורה [lineIndex] (0-based), לפי סדר הופעתם.
  List<DivineNameSpan> spansAt(int lineIndex) {
    var low = 0;
    var high = _lines.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_lines[mid] < lineIndex) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low >= _lines.length || _lines[low] != lineIndex) return const [];
    return [
      for (var i = _lineStarts[low]; i < _lineStarts[low + 1]; i++)
        (start: _data[i * 3], end: _data[i * 3 + 1], kind: _data[i * 3 + 2]),
    ];
  }
}

/// בונה [DivineNameSpans] משורות שמגיעות ממוינות לפי (lineIndex, start).
class DivineNameSpansBuilder {
  final _lines = <int>[];
  final _lineStarts = <int>[];
  final _data = <int>[];

  void add(int lineIndex, int start, int end, int kind) {
    _requireInt32(lineIndex);
    _requireInt32(start);
    _requireInt32(end);
    _requireInt32(kind);
    if (start < 0 || end <= start) return;
    if (_lines.isEmpty || _lines.last != lineIndex) {
      // קלט לא ממוין היה שובר את החיפוש הבינארי — מדלגים במקום לשבש.
      if (_lines.isNotEmpty && lineIndex < _lines.last) return;
      _lines.add(lineIndex);
      _lineStarts.add(_data.length ~/ 3);
    }
    _data
      ..add(start)
      ..add(end)
      ..add(kind);
  }

  DivineNameSpans build() {
    if (_lines.isEmpty) return DivineNameSpans.empty;
    return DivineNameSpans._(
      Int32List.fromList(_lines),
      Int32List.fromList([..._lineStarts, _data.length ~/ 3]),
      Int32List.fromList(_data),
    );
  }
}
