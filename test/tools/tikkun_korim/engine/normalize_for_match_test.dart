/// נרמול המילים שמאתר את פתיחות הפרשות: זהה לשרשרת ה-RegExp.
library;

import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

final RegExp _kqMarks = RegExp('[\u{E010}-\u{E012}]');
final RegExp _nikudAndMaqaf = RegExp('[֑-ׇ־]');
final RegExp _zeiraRabati = RegExp('[\u{E020}-\u{E023}]');
final RegExp _maskedName = RegExp('יקוק');

String _regexNormalize(String s) => s
    .replaceAll(_kqMarks, '')
    .replaceAll(_nikudAndMaqaf, '')
    .replaceAll(_zeiraRabati, '')
    .replaceAll(_maskedName, 'יהוה');

void main() {
  const books = ['bereshit', 'shemot', 'vayikra', 'bamidbar', 'devarim'];
  late List<String> words;

  setUpAll(() {
    words = [
      for (final id in books)
        for (final token in tokenizeBook(
          readFixture(id),
          fixtureBookNames[id]!,
        ))
          if (token.type == TikkunTokenType.word) token.value!,
    ];
  });

  test('זהה לשרשרת ה-RegExp בכל מילות התורה ובמקרי קצה', () {
    const edges = [
      '',
      'בְּרֵאשִׁ֖ית',
      'יְקֹוָ֥ק',
      'יְקֹוָק',
      'אֶל־',
      '\u{E010}הוּא\u{E011}הִיא\u{E012}',
      '\u{E022}ב\u{E023}ְּרֵאשִׁית',
      'יקוקיקוק',
      // גבולות הטווחים מבפנים ומבחוץ.
      'א\u0590\u0591\u05C7\u05C8ב',
      'א\u{E00F}\u{E010}\u{E012}\u{E013}ב',
      'א\u{E01F}\u{E020}\u{E023}\u{E024}ב',
    ];
    for (final word in [...edges, ...words]) {
      expect(
        normalizeForMatch(word),
        _regexNormalize(word),
        reason: escapeNonAscii(word),
      );
    }
  });
}
