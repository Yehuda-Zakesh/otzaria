import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/utils/banner_title.dart';

void main() {
  // הערכים המצופים חושבו ב-URLEncoder של Java, כמו במחולל של SeforimLibrary.
  test('{title} מקודד בתוך יעד קישור ונשאר כלשונו בשאר הטקסט', () {
    expect(
      expandBannerTitle(
        'על ספר {title} ב&ג [כאן](https://w.org/wiki/{title}.html) '
            '[שוב](x?t={title})',
        'א (ב)',
      ),
      'על ספר א (ב) ב&ג [כאן](https://w.org/wiki/%D7%90%20%28%D7%91%29.html) '
      '[שוב](x?t=%D7%90%20%28%D7%91%29)',
    );
    expect(
      expandBannerTitle('[a](u?q={title})', '#?&)'),
      '[a](u?q=%23%3F%26%29)',
    );
    expect(expandBannerTitle('ללא תבנית', 'x'), 'ללא תבנית');
  });

  test('תווים שנשמרים, + ותו מחוץ ל-BMP — כמו ב-Java', () {
    expect(
      expandBannerTitle(
        '[{title}](u/{title})\n[b](v/{title})',
        "aZ09.-*_~+ '📖",
      ),
      "[aZ09.-*_~+ '📖](u/aZ09.-*_%7E%2B%20%27%F0%9F%93%96)\n"
      '[b](v/aZ09.-*_%7E%2B%20%27%F0%9F%93%96)',
    );
  });

  test(
    'surrogate בודד מקודד כ-%3F בקישור ונשאר כלשונו מחוצה לו',
    () {
      const title = 'a\uD800b\uDC00c\uD83D\uDCD6';
      expect(
        expandBannerTitle('{title} [x](u/{title})', title),
        '$title [x](u/a%3Fb%3Fc%F0%9F%93%96)',
      );
    },
  );
}
