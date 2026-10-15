// רשימת ההיתר של CSS — **מקבעת את שני הכיוונים**.
//
// כיוון אחד: תכונה שמנוע התצוגה מכיר חייבת לשרוד את ההמרה. הרגרסיה שהוא
// מונע היא מסנן שמהדק יתר על המידה, ואז ספר שעוצב כהלכה מגיע לקורא קירח.
//
// הכיוון השני, החשוב יותר: ערך שמגיע מתוך מסמך שהמשתמש הוריד מהאינטרנט
// אינו אמור להגיע לגוף הספר בלי אימות. ערך שמצליח לצאת מה-`style="…"`
// מזריק תגיות משלו — ומשם הן מגיעות גם לתוכן העניינים ולאינדקס.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/css_whitelist.dart';

/// מריץ את המסנן על הצהרה בודדת ומחזיר את הפלט, או null.
String? filter(String property, String value, {bool blockOnly = false}) =>
    cssStyleFrom({property: value}, blockOnly: blockOnly);

void main() {
  group('תכונות שהקורא מכיר — חייבות לשרוד', () {
    const survives = {
      'color': '#8b0000',
      'background-color': 'rgba(255,0,0,0.2)',
      'font-weight': '600',
      'font-style': 'italic',
      'font-size': '150%',
      'font-family': "'sbl hebrew', david, serif",
      'line-height': '1.5',
      'vertical-align': 'super',
      'white-space': 'nowrap',
      'display': 'inline-block',
      'direction': 'ltr',
      'text-decoration': 'underline overline',
      'text-decoration-style': 'wavy',
      'text-decoration-color': 'red',
      'text-decoration-thickness': '250%',
      'text-shadow': '2px 2px 4px gray',
      'list-style-type': 'hebrew',
      'border': '1px solid #8b0000',
      'border-right': '4px solid #b8860b',
      'padding': '5px 10px 15px 20px',
      'padding-right': '12px',
      'margin': '8px',
      'width': '24px',
      'height': '24px',
    };

    for (final entry in survives.entries) {
      test('${entry.key}: ${entry.value}', () {
        expect(
          filter(entry.key, entry.value),
          '${entry.key}: ${entry.value}',
          reason: 'תכונה שהקורא מציג נמחקה בהמרה',
        );
      });
    }

    test('text-align שורד על בלוק ונדחה על inline', () {
      // המדריך: יישור עובד רק על תגי בלוק; על `<span>` הוא אינו עושה דבר.
      expect(filter('text-align', 'center', blockOnly: true), isNotNull);
      expect(filter('text-align', 'center'), isNull);
    });

    test('כמה הצהרות מצטרפות לערך אחד, מופרדות בנקודה-פסיק', () {
      expect(
        cssStyleFrom({'font-size': '130%', 'line-height': '1.5'}),
        'font-size: 130%; line-height: 1.5',
      );
    });

    test('skip מוציא תכונה שכבר הומרה לתגית', () {
      expect(
        cssStyleFrom(
          {
            'font-weight': 'bold',
            'font-size': '120%',
          },
          skip: {'font-weight'},
        ),
        'font-size: 120%',
      );
    });
  });

  group('מה שהמדריך מציין כלא-נתמך — נדחה ואינו נכתב', () {
    const rejected = {
      // הצהרה מתה: הקורא מתעלם ממנה, וכתיבתה רק מנפחת כל שורה.
      'font-size': '1.5rem',
      'font-style': 'oblique',
      'font-weight': 'bolder',
      'text-decoration-thickness': '3px',
      // חמישה ערכים בצל — הקורא מבטל את כל התכונה.
      'text-shadow': '1px 1px 1px 1px red',
      'list-style-type': 'katakana',
      'vertical-align': '17%',
    };

    for (final entry in rejected.entries) {
      test('${entry.key}: ${entry.value}', () {
        expect(filter(entry.key, entry.value), isNull);
      });
    }

    test('font-weight מקבל רק כפולות של 100 בטווח', () {
      expect(filter('font-weight', '650'), isNull);
      expect(filter('font-weight', '1000'), isNull);
      expect(filter('font-weight', '0'), isNull);
      expect(filter('font-weight', '900'), isNotNull);
    });
  });

  group('תכונות מתקדמות שאינן נתמכות — נעלמות מאליהן', () {
    const unknown = [
      'transform',
      'position',
      'float',
      'opacity',
      'border-radius',
      'animation',
      'text-emphasis',
      'text-emphasis-style',
      'background-image',
      'content',
      'z-index',
      'overflow',
      'filter',
      'zoom',
    ];

    for (final property in unknown) {
      test(property, () {
        expect(filter(property, 'whatever'), isNull);
      });
    }
  });

  group('אבטחה — ערך אינו יכול לצאת מהמאפיין', () {
    test('גרשיים בערך נדחים ואינם נכתבים', () {
      expect(filter('color', 'red;"onmouseover="x()'), isNull);
      expect(filter('font-family', "david'\"onload=x"), isNull);
    });

    test('url() נדחה בכל תכונה שיכולה לשאת אותו', () {
      for (final property in const [
        'background',
        'background-color',
        'border',
        'text-shadow',
      ]) {
        expect(
          filter(property, 'url(https://evil.example/p.png)'),
          isNull,
          reason: property,
        );
      }
    });

    test('expression() ותחביר JavaScript נדחים', () {
      expect(filter('color', 'expression(alert(1))'), isNull);
      expect(filter('width', 'javascript:alert(1)'), isNull);
    });

    test('הערת CSS אינה יכולה להבריח ערך', () {
      expect(filter('color', 'red/*'), isNull);
      expect(filter('font-size', '10px/*x*/'), isNull);
    });

    test('סוגריים לא מאוזנים בפונקציית צבע נדחים', () {
      expect(filter('color', 'rgb(1,2,3'), isNull);
      expect(filter('color', 'rgb(1,2,3))'), isNull);
      expect(filter('color', 'rgb(1,2)'), isNull);
      expect(filter('color', 'rgb(1,2,3)'), isNotNull);
    });

    test('שם גופן מרובה-מילים נכתב מחדש במרכאות בודדות', () {
      // גרש כפול מתוך המסמך אינו נכנס אל תוך `style="…"`.
      expect(
        filter('font-family', '"Taamey David CLM", serif'),
        "font-family: 'Taamey David CLM', serif",
      );
    });

    test('מרכאות לא מאוזנות בשם גופן נדחות', () {
      expect(filter('font-family', "'David"), isNull);
      expect(filter('font-family', "'Da'vid'"), isNull);
    });

    test('מידה עם יחידה לא מוכרת נדחית', () {
      for (final value in const ['10vw', '10vh', '10ch', '10q', '10']) {
        final result = filter('padding-top', value);
        if (value == '10') {
          expect(result, isNotNull, reason: 'מספר חשוף הוא מידה חוקית');
        } else {
          expect(result, isNull, reason: value);
        }
      }
    });

    test('מספר ההצהרות אינו משנה את תקינות הסינון', () {
      final declarations = {
        for (var i = 0; i < 200; i++) 'unknown-$i': 'value',
        'color': 'red',
      };
      expect(cssStyleFrom(declarations), 'color: red');
    });
  });

  group('מאפיין מבני מספרי', () {
    test('מקבל מספר חיובי בלבד', () {
      expect(positiveIntegerAttribute('24'), '24');
      expect(positiveIntegerAttribute(' 8 '), '8');
      expect(positiveIntegerAttribute('0'), isNull);
      expect(positiveIntegerAttribute('-3'), isNull);
      expect(positiveIntegerAttribute('24px'), isNull);
      expect(positiveIntegerAttribute('2"onerror="x'), isNull);
      expect(positiveIntegerAttribute(null), isNull);
    });
  });
}
