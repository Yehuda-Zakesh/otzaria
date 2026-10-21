import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

void main() {
  setUp(() => variantNoteScans = 0);

  test('ספר בלי הערות חילוף אינו נסרק בביטויי הנוסח', () {
    final raw = readFixture('yeshayahu');
    cleanRawText(raw, tradition: TikkunTradition.ashkenazSephard);
    applyMegillahNusach(raw, 'ashkenaz');
    expect(variantNoteScans, 0);
  });

  test('ספר עם הערות חילוף נסרק', () {
    cleanRawText(
      readFixture('bereshit'),
      tradition: TikkunTradition.ashkenazSephard,
    );
    applyMegillahNusach(readFixture('esther'), 'ashkenaz');
    expect(variantNoteScans, 2);
  });

  for (final name in ['yeshayahu', 'shoftim', 'shmuel_b']) {
    test('$name — בחירת מסורת בלי הערות חילוף אינה משנה את הניקוי', () {
      final raw = readFixture(name);
      for (final tradition in TikkunTradition.values) {
        expect(cleanRawText(raw, tradition: tradition), cleanRawText(raw));
      }
      expect(applyMegillahNusach(raw, 'ashkenaz'), raw);
    });
  }
}
