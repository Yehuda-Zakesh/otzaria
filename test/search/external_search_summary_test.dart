import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/external_search_summary.dart';

ExternalSearchSummary _summary({
  List<ExternalSearchBook> namedOtherBooks = const [],
}) => ExternalSearchSummary(
  sourceTitle: 'היברובוקס',
  totalBooks: 4,
  categoryBookCounts: const {'/הלכה': 1},
  otherBooks: 3,
  namedOtherBooks: namedOtherBooks,
);

void main() {
  group('ExternalSearchSummary', () {
    test('דלי "עוד מ" ו-facet הספר שתחתיו נגזרים משם המקור', () {
      final summary = _summary();
      expect(summary.otherCategoryTitle, 'עוד מהיברובוקס');
      expect(summary.otherCategoryFacet, '/עוד מהיברובוקס');
      expect(summary.bookFacetOf(42), '/עוד מהיברובוקס/#42');
    });

    test('facet של ספר בדלי מפוענח בחזרה למזהה', () {
      final summary = _summary();
      expect(summary.bookIdOfFacet('/עוד מהיברובוקס/#42'), 42);
    });

    test('facet אחר אינו מפוענח כספר בדלי', () {
      final summary = _summary();
      expect(summary.bookIdOfFacet('/עוד מהיברובוקס'), isNull);
      expect(summary.bookIdOfFacet('/הלכה/#42'), isNull);
      // מפתח ספר של הספרייה אינו מזהה בדלי.
      expect(summary.bookIdOfFacet('/עוד מהיברובוקס/id:42'), isNull);
      expect(summary.bookIdOfFacet('/עוד מהיברובוקס/#לא-מספר'), isNull);
    });

    test('בלי שמות מהספק אין ספרים לפרוש תחת הדלי', () {
      expect(_summary().namedOtherBooks, isEmpty);
      expect(
        _summary(
          namedOtherBooks: const [
            ExternalSearchBook(id: 7, title: 'ספר', hits: 2),
          ],
        ).namedOtherBooks.single.title,
        'ספר',
      );
    });
  });
}
