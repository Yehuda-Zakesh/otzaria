import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';

/// המבנה הדחוס של מופעי השמות: חיפוש לפי שורה, סדר, וקלט פגום.
void main() {
  test('פענוח span — אותם ערכים כמו DivineSpanCodeTest ב-SeforimLibrary', () {
    expect(decodeDivineNameSpan(0, 145), (end: 1, kind: DivineNameKind.hvyh));
    expect(
      decodeDivineNameSpan(149759, 1737),
      (end: 149772, kind: DivineNameKind.yah),
    );
    expect(
      decodeDivineNameSpan(10, 677),
      (end: 15, kind: DivineNameKind.elohim),
    );
    // אורך מרבי (2^24 - 1), מקור 4, סוג 9.
    expect(
      decodeDivineNameSpan(0, 2147483593),
      (end: 16777215, kind: DivineNameKind.yah),
    );
  });

  test(
    'span פגום — FormatException, כמו DivineSpanCodeTest ב-SeforimLibrary',
    () {
      int span(int length, int source, int kind) =>
          (length << 7) | (source << 4) | kind;
      expect(decodeDivineNameSpan(1, span(2, 3, 8)), (end: 3, kind: 8));
      for (final (start, bad) in [
        (0, span(0, 1, 1)), // אורך 0
        (0, span(2, 0, 1)), // מקור 0
        (0, span(2, 1, 0)), // סוג 0
        (0, -1),
        (0, 0x80000000), // מעבר ל-31 ביט
        (0, 1 << 40),
        (-1, span(2, 1, 1)),
        (0x7FFFFFFF, span(1, 1, 1)), // הקצה עובר את Int32
      ]) {
        expect(
          () => decodeDivineNameSpan(start, bad),
          throwsFormatException,
          reason: 'span $bad at $start',
        );
      }
    },
  );

  test('סוג ומקור לא מוכרים — עוברים כמות שהם (תאימות קדימה)', () {
    expect(decodeDivineNameSpan(0, (2 << 7) | (5 << 4) | 1), (end: 2, kind: 1));
    expect(decodeDivineNameSpan(0, (2 << 7) | (7 << 4) | 15), (
      end: 2,
      kind: 15,
    ));
    expect(decodeDivineNameSpan(4, (3 << 7) | (1 << 4) | 10), (
      end: 7,
      kind: 10,
    ));
  });

  test('ערך שאינו נכנס ב-Int32 — FormatException במקום עטיפה שקטה', () {
    for (final add in <void Function(DivineNameSpansBuilder)>[
      (b) => b.add(1 << 31, 0, 1, 1),
      (b) => b.add(0, 1 << 31, (1 << 31) + 1, 1),
      (b) => b.add(0, 0, 1 << 31, 1),
      (b) => b.add(0, 0, 1, 1 << 32),
    ]) {
      expect(() => add(DivineNameSpansBuilder()), throwsFormatException);
    }
  });

  test('ריק — אין מופעים בשום שורה', () {
    final spans = DivineNameSpansBuilder().build();
    expect(spans.isEmpty, isTrue);
    expect(identical(spans, DivineNameSpans.empty), isTrue);
    expect(spans.spansAt(0), isEmpty);
  });

  test('המופעים של כל שורה, לפי הסדר', () {
    final builder = DivineNameSpansBuilder()
      ..add(2, 0, 4, 1)
      ..add(2, 10, 15, 5)
      ..add(7, 3, 6, 7)
      ..add(100, 1, 3, 3);
    final spans = builder.build();

    expect(spans.length, 4);
    expect(spans.spansAt(2), [
      (start: 0, end: 4, kind: 1),
      (start: 10, end: 15, kind: 5),
    ]);
    expect(spans.spansAt(7), [(start: 3, end: 6, kind: 7)]);
    expect(spans.spansAt(100), [(start: 1, end: 3, kind: 3)]);
    for (final missing in [-1, 0, 1, 3, 8, 99, 101]) {
      expect(spans.spansAt(missing), isEmpty, reason: 'line $missing');
    }
  });

  test('טווח ריק או שלילי, ושורה שחוזרת אחורה — מדולגים', () {
    final spans =
        (DivineNameSpansBuilder()
              ..add(1, 5, 5, 1)
              ..add(1, -1, 3, 1)
              ..add(3, 0, 2, 3)
              ..add(2, 0, 2, 3))
            .build();
    expect(spans.length, 1);
    expect(spans.spansAt(3), [(start: 0, end: 2, kind: 3)]);
    expect(spans.spansAt(2), isEmpty);
  });
}
