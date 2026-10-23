import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:pdfrx/pdfrx.dart';

PdfTextSearchResult _match(int page) => PdfTextSearchResult.fromRange(
  PdfPageTextRange(
    pageText: PdfPageText(
      pageNumber: page,
      fullText: 'שלום עולם',
      charRects: List.filled(9, const PdfRect(0, 1, 1, 0)),
      fragments: const [],
    ),
    start: 0,
    end: 4,
  ),
);

PdfTextSearchResult _rangeIn(String fullText, String word) {
  final start = fullText.indexOf(word);
  return PdfTextSearchResult.fromRange(
    PdfPageTextRange(
      pageText: PdfPageText(
        pageNumber: 1,
        fullText: fullText,
        charRects: List.filled(fullText.length, const PdfRect(0, 1, 1, 0)),
        fragments: const [],
      ),
      start: start,
      end: start + word.length,
    ),
    contextLength: 160,
  );
}

class _InvalidMatch extends Fake implements PdfTextSearchResult {
  @override
  String get contextText => 'קצר';
  @override
  int get contextStart => 0;
  @override
  int get start => 2;
  @override
  int get end => 99;
}

void main() {
  group('matchLineSnippet — שורת ההקשר של תוצאה', () {
    const page = 'שורה ראשונה\nבראשית ברא אלהים\nשורה אחרונה';

    test('מחזיר את השורה שבה ההתאמה', () {
      expect(
        PdfBookSearchView.matchLineSnippet(_rangeIn(page, 'ברא '), 'ברא'),
        'בראשית ברא אלהים',
      );
    });

    test('התאמה בתחילת הטקסט ובסופו', () {
      expect(
        PdfBookSearchView.matchLineSnippet(_rangeIn(page, 'שורה'), 'x'),
        'שורה ראשונה',
      );
      expect(
        PdfBookSearchView.matchLineSnippet(_rangeIn(page, 'אחרונה'), 'x'),
        'שורה אחרונה',
      );
    });

    test('טווח לא תקין — חוזר לשאילתה', () {
      final broken = _InvalidMatch();
      expect(PdfBookSearchView.matchLineSnippet(broken, 'שאילתה'), 'שאילתה');
    });

    test('שכבת טקסט ללא שורות אינה משכפלת עמוד שלם לכל התאמה', () {
      final page =
          '${List.filled(10000, 'א').join()}שלום${List.filled(10000, 'ב').join()}';
      final match = _rangeIn(page, 'שלום');
      final snippet = PdfBookSearchView.matchLineSnippet(match, 'שלום');
      expect(match.contextText.length, 324);
      expect(match.pageTextLength, page.length);
      expect(
        snippet,
        '…${List.filled(80, 'א').join()}שלום${List.filled(156, 'ב').join()}…',
      );
      expect(snippet.length, 242);
    });
  });

  group('keptMatchCount — מיפוי מצטבר של תוצאות החיפוש הפשוט', () {
    final page2 = _match(2);
    final page5a = _match(5);
    final page5b = _match(5);

    test('רשימה מצטברת של אותו חיפוש שומרת את מה שכבר מופה', () {
      expect(
        PdfBookSearchView.keptMatchCount(
          List.unmodifiable([page2]),
          List.unmodifiable([page2, page5a, page5b]),
        ),
        1,
      );
    });

    test('עמוד בלי התאמות חדשות שומר הכול', () {
      final list = [page2, page5a];
      expect(
        PdfBookSearchView.keptMatchCount(
          List.unmodifiable(list),
          List.unmodifiable(list),
        ),
        2,
      );
    });

    test('חיפוש חדש (אובייקטים אחרים) בונה מחדש', () {
      expect(
        PdfBookSearchView.keptMatchCount(
          List.unmodifiable([page2, page5a]),
          List.unmodifiable([_match(2), _match(5), _match(7)]),
        ),
        0,
      );
    });

    test('רשימה שהתקצרה או ריקה בונה מחדש', () {
      expect(
        PdfBookSearchView.keptMatchCount(
          List.unmodifiable([page2, page5a]),
          List.unmodifiable([page2]),
        ),
        0,
      );
      expect(PdfBookSearchView.keptMatchCount(const [], [page2]), 0);
    });
  });
}
