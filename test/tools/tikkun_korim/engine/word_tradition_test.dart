import 'package:otzaria/tools/tikkun_korim/tikkun_korim.dart';
import 'package:test/test.dart';

import '../support/tikkun_fixtures.dart';

List<String> _verseWords(
  List<TikkunToken> tokens,
  int chapter,
  int verse,
) {
  var ch = 0;
  var vs = 0;
  final words = <String>[];
  for (final token in tokens) {
    if (token.type == TikkunTokenType.chapterBreak) ch = token.chapterNum!;
    if (token.type == TikkunTokenType.verseBreak) vs = token.verseNum!;
    if (token.isWord && ch == chapter && vs == verse) words.add(token.value!);
  }
  return words;
}

void main() {
  const variants = [
    ('bereshit', 4, 13, 'מנשא', 'מנשוא'),
    ('bereshit', 7, 11, 'מעינת', 'מעינות'),
    ('bereshit', 9, 29, 'ויהיו', 'ויהי'),
    ('shemot', 25, 31, 'תעשה', 'תיעשה'),
    ('shemot', 28, 26, 'האפד', 'האפוד'),
    ('bamidbar', 1, 17, 'בשמת', 'בשמות'),
    ('bamidbar', 10, 10, 'חדשיכם', 'חדשכם'),
    ('bamidbar', 22, 5, 'בער', 'בעור'),
    ('devarim', 23, 2, 'דכא', 'דכה'),
  ];

  for (final tradition in TikkunTradition.values) {
    group(tradition.id, () {
      final byBook = <String, List<TikkunToken>>{};
      setUpAll(() {
        for (final id in TikkunData.booksOrder) {
          byBook[id] = tokenizeBook(
            readFixture(id),
            fixtureBookNames[id]!,
            tradition: tradition,
          );
        }
      });

      for (final (id, chapter, verse, yemen, ashkenaz) in variants) {
        test('$id $chapter:$verse — כתיב לפי מסורת', () {
          final words = _verseWords(
            byBook[id]!,
            chapter,
            verse,
          ).map(stripNikud).toList();
          final isYemen = tradition == TikkunTradition.yemen;
          expect(words, contains(isYemen ? yemen : ashkenaz));
          expect(words, isNot(contains(isYemen ? ashkenaz : yemen)));
        });
      }

      test('ניקוד וטעמים וגבול הפסוק של ימי נח נשמרים', () {
        final words = _verseWords(byBook['bereshit']!, 9, 29);
        expect(
          words.first,
          tradition == TikkunTradition.yemen ? 'וַיִּֽהְיוּ֙' : 'וַֽיְהִי֙',
        );
        expect(words.last, 'וַיָּמֹֽת׃');
      });

      for (final (chapter, verse) in [(41, 45), (41, 50), (46, 20)]) {
        test('בראשית $chapter:$verse — פוטיפרע בתיבה אחת רק בתימן', () {
          final words = _verseWords(
            byBook['bereshit']!,
            chapter,
            verse,
          ).map(stripNikud).toList();
          if (tradition == TikkunTradition.yemen) {
            expect(words, contains('פוטיפרע'));
            expect(words, isNot(contains('פוטי')));
          } else {
            expect(words, containsAllInOrder(['פוטי', 'פרע']));
            expect(words, isNot(contains('פוטיפרע')));
          }
        });
      }

      test('דברים לב:ו — צירוף ה״א השאלה בתימן', () {
        final words = _verseWords(byBook['devarim']!, 32, 6);
        final plain = words
            .map(stripNikud)
            .map(
              (word) => word.replaceAll(RegExp('[\uE020-\uE023]'), ''),
            );
        if (tradition == TikkunTradition.yemen) {
          expect(plain, contains('הליהוה'));
          expect(plain, isNot(contains('ה')));
        } else {
          expect(plain, containsAllInOrder(['ה', 'ליהוה']));
        }
      });

      for (final (id, chapter, verse, word, marker, inYemen) in const [
        ('bereshit', 5, 1, 'ספר', kRabatiStart, true),
        ('shemot', 34, 7, 'נצר', kRabatiStart, false),
        ('vayikra', 6, 2, 'מוקדה', kZeiraStart, false),
        ('bamidbar', 25, 11, 'פינחס', kZeiraStart, false),
        ('devarim', 11, 21, 'הארץ', kRabatiStart, true),
        ('devarim', 22, 6, 'קן', kRabatiStart, true),
        ('devarim', 33, 29, 'אשריך', kRabatiStart, true),
      ]) {
        test('$id $chapter:$verse — אותיות גדולות וקטנות לפי מסורת', () {
          final original = _verseWords(byBook[id]!, chapter, verse).singleWhere(
            (w) =>
                stripNikud(w).replaceAll(RegExp('[\uE020-\uE023]'), '') == word,
          );
          expect(
            original.contains(String.fromCharCode(marker)),
            inYemen == (tradition == TikkunTradition.yemen),
          );
        });
      }

      test('הערה לפני קן אינה מחליפה את המילה שלפניה', () {
        expect(
          _verseWords(byBook['devarim']!, 22, 6).map(stripNikud),
          contains('יקרא'),
        );
      });
    });
  }

  test('הערה כללית אינה נבלעת בחילוף הנוסח שבהערה הבאה', () {
    const marker = '<sup class="footnote-marker">*</sup>';
    final words = tokenizeBook(
      'אבג$marker<i class="footnote">(הערה כללית)</i> '
          'דהו$marker<i class="footnote">(בספרי ספרד ואשכנז זחט)</i> יכל׃',
      'בראשית',
    ).where((token) => token.isWord).map((token) => token.value);
    expect(words, ['אבג', 'זחט', 'יכל׃']);
  });

  test('ניקוי ללא בחירת מסורת שומר את נוסח המקור', () {
    final words = _verseWords(
      tokenizeText(cleanRawText(readFixture('bereshit'))),
      9,
      29,
    );
    expect(words.first, 'וַיִּֽהְיוּ֙');
  });

  for (final nusach in ['ashkenaz', 'sephard']) {
    for (final (chapter, verse, source, ashkenaz) in const [
      (8, 11, 'ולהרג', 'להרג'),
      (9, 2, 'לפניהם', 'בפניהם'),
    ]) {
      test('אסתר $chapter:$verse — נוסח $nusach', () {
        final words = _verseWords(
          tokenizeBook(
            applyMegillahNusach(readFixture('esther'), nusach),
            'אסתר',
          ),
          chapter,
          verse,
        ).map(stripNikud);
        expect(words, contains(nusach == 'ashkenaz' ? ashkenaz : source));
        expect(
          words,
          isNot(contains(nusach == 'ashkenaz' ? source : ashkenaz)),
        );
      });
    }
  }
}
