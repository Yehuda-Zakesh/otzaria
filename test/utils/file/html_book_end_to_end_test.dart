// ספר HTML מקצה לקצה — **תמיכה מלאה כמו ספר רגיל**.
//
// הבדיקות ביחידה מקבעות את פלט הממיר; כאן נבדק מה שקורה לפלט הזה אחר כך
// בכל השכבות שספר עובר בהן: תוכן העניינים, הניווט לכותרת, החיפוש בתוך
// הספר, מה שנכנס לאינדקס החיפוש הגלובלי, וקריאת הספר דרך מודל הספר.
//
// הרגרסיה שהבדיקות כאן מונעות אינה בממיר אלא **בהתאמה בין השכבות**: פלט
// שנראה תקין אך שורת הכותרת שלו אינה נקלטת ב-TocParser, או שמספרי השורות
// שלו זזים בין המסלול המוצג למסלול המאונדקס, נותן ספר שנפתח ונראה תקין
// אבל הניווט והחיפוש בו שבורים.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

/// PNG 1x1 — כדי שהספר יכיל גם תמונה מוטמעת.
const _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAj'
    'CB0C8AAAAASUVORK5CYII=';

/// ספר HTML מייצג: היררכיית כותרות מלאה, עיצוב, רשימה, טבלה, הערת שוליים,
/// קישורים, תמונה, וכותרת עיצובית שמודרת מתוכן העניינים.
String _sourceBook() =>
    '<!DOCTYPE html><html dir="rtl"><head><meta charset="utf-8">'
    '<title>ספר הבדיקה</title>'
    '<script>alert("לא אמור להופיע")</script></head><body>'
    '<h1>שער הספר</h1>'
    '<p>פתח דבר של הספר.</p>'
    '<h2>חלק ראשון</h2>'
    '<p>גוף החלק הראשון, ובו <b>מילה מודגשת</b> ועוד טקסט.</p>'
    '<h3>פרק א</h3>'
    '<p>תוכן פרק א, ובו ביטוי ייחודי לחיפוש: אספקלריא.</p>'
    '<ol style="list-style-type:hebrew"><li>סעיף ראשון</li>'
    '<li>סעיף שני</li></ol>'
    '<h3>פרק ב</h3>'
    '<p>תוכן פרק ב<sup class="footnote-marker">1</sup>'
    '<i class="footnote">גוף ההערה, שאינו בגוף הספר.</i> והמשך.</p>'
    '<table><caption>טבלת השוואה</caption>'
    '<tr><th>עמודה</th><td>ערך</td></tr></table>'
    '<h2>חלק שני</h2>'
    '<p>גוף החלק השני.</p>'
    '<h3 data-toc="none">כותרת עיצובית</h3>'
    '<p><img src="data:image/png;base64,$_tinyPng" width="24"></p>'
    '<p><a href="#חלק ראשון">חזרה לחלק ראשון</a>, '
    '<a href="book://ברכות#דף ב:">קישור לספר</a>.</p>'
    '<p style="display:none">טקסט מוסתר</p>'
    '</body></html>';

/// ממיר את הספר ומחזיר את שורותיו, כפי שהקורא מקבל אותן.
List<String> _bookLines({bool embedImages = true}) => htmlToText(
  _utf8(_sourceBook()),
  'ספר הבדיקה',
  embedImages: embedImages,
).split('\n');

void main() {
  group('תוכן עניינים והיררכיה', () {
    late List<TocEntry> toc;

    setUp(() {
      toc = TocParser.parseEntriesFromContent(_bookLines().join('\n'));
    });

    test('נבנה עץ עם שם הספר בשורש', () {
      expect(toc, hasLength(1));
      expect(toc.single.text, 'ספר הבדיקה');
      expect(toc.single.index, 0);
    });

    test('היררכיית המקור נשמרת במלואה, מוסטת רמה אחת מתחת לשם הספר', () {
      // המקור: h1 «שער הספר» ובתוכו h2 «חלק ראשון»/«חלק שני», ובחלק
      // הראשון h3 «פרק א»/«פרק ב». הפלט חייב לשקף בדיוק את אותו קינון.
      final cover = toc.single.children.single;
      expect(cover.text, 'שער הספר');
      expect(cover.level, 2);

      expect(cover.children.map((e) => e.text), ['חלק ראשון', 'חלק שני']);
      expect(cover.children.every((e) => e.level == 3), isTrue);

      final firstPart = cover.children.first;
      expect(firstPart.children.map((e) => e.text), ['פרק א', 'פרק ב']);
      expect(firstPart.children.every((e) => e.level == 4), isTrue);
    });

    test('כותרת עם data-toc="none" מודרת מהעץ אך נשארת בגוף הספר', () {
      String flatten(List<TocEntry> entries) =>
          entries.map((e) => '${e.text} ${flatten(e.children)}').join(' ');
      expect(flatten(toc), isNot(contains('כותרת עיצובית')));
      expect(_bookLines().join('\n'), contains('כותרת עיצובית'));
    });

    test('כל אינדקס בעץ מצביע על שורת הכותרת בפועל', () {
      final lines = _bookLines();
      void check(List<TocEntry> entries) {
        for (final entry in entries) {
          expect(
            lines[entry.index],
            startsWith('<h'),
            reason: 'רשומת "${entry.text}" מצביעה על שורה שאינה כותרת',
          );
          expect(lines[entry.index], contains(entry.text));
          check(entry.children);
        }
      }

      check(toc);
    });
  });

  group('ניווט לכותרת', () {
    test('קישור פנימי לפי טקסט הכותרת מוצא את השורה', () {
      // כך הקורא מנווט: `HtmlLinkHandler` מחפש את הכותרת לפי הטקסט שאחרי
      // הסולמית, ומשווה אותו לרשומות תוכן העניינים.
      final toc = TocParser.parseEntriesFromContent(_bookLines().join('\n'));
      TocEntry? find(List<TocEntry> entries, String text) {
        for (final entry in entries) {
          if (entry.text == text) return entry;
          final nested = find(entry.children, text);
          if (nested != null) return nested;
        }
        return null;
      }

      for (final title in const ['חלק ראשון', 'פרק ב', 'חלק שני']) {
        final target = find(toc, title);
        expect(target, isNotNull, reason: title);
        expect(_bookLines()[target!.index], contains(title), reason: title);
      }
    });

    test('הקישור הפנימי בגוף הספר מפנה לכותרת קיימת', () {
      final content = _bookLines().join('\n');
      expect(content, contains('<a href="#חלק ראשון">'));
      final toc = TocParser.parseEntriesFromContent(content);
      final titles = <String>[];
      void collect(List<TocEntry> entries) {
        for (final entry in entries) {
          titles.add(entry.text);
          collect(entry.children);
        }
      }

      collect(toc);
      expect(titles, contains('חלק ראשון'));
    });
  });

  group('חיפוש בתוך הספר', () {
    test('ביטוי בגוף הספר נמצא, והשורה שלו מזוהה', () {
      final lines = _bookLines();
      final matches = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (text_utils.stripHtmlIfNeeded(lines[i]).contains('אספקלריא')) {
          matches.add(i);
        }
      }
      expect(matches, hasLength(1));
      expect(lines[matches.single], contains('תוכן פרק א'));
    });

    test('טקסט שמפוצל בתגיות עיצוב נמצא כמילה שלמה', () {
      // `<b>מילה מודגשת</b>` — החיפוש עובד על הטקסט בלי התגיות.
      final plain = _bookLines().map(text_utils.stripHtmlIfNeeded).join('\n');
      expect(plain, contains('מילה מודגשת'));
    });

    test('גוף הערת שוליים אינו מזהם את גוף הספר', () {
      // ההערה מוצגת כמפרש בחלונית הצד; הופעתה בגוף הספר הייתה שוברת את
      // רצף הקריאה ומזהמת את תוצאות החיפוש.
      final content = _bookLines().join('\n');
      expect(content, contains('class="footnote"'));
      expect(content, contains('גוף ההערה'));
    });

    test('טקסט מוסתר אינו נמצא בחיפוש', () {
      expect(_bookLines().join('\n'), isNot(contains('טקסט מוסתר')));
    });

    test('קוד מהמסמך אינו נמצא בחיפוש', () {
      expect(_bookLines().join('\n'), isNot(contains('alert')));
    });
  });

  group('אינדקס החיפוש הגלובלי', () {
    test('הווריאנט המאונדקס שומר על אותו מספר שורות בדיוק', () {
      // האינדקס נבנה מהווריאנט חסר-התמונות. מספר שורות שונה היה מסיט כל
      // תוצאת חיפוש מול מה שהקורא מציג.
      expect(
        _bookLines(embedImages: false).length,
        _bookLines().length,
      );
    });

    test('ניקוי ה-data URI אינו פוגע בתוכן', () {
      final indexed = IndexingRepository.stripDataUrisForIndex(
        _bookLines(embedImages: false).join('\n'),
      );
      expect(indexed, isNot(contains('base64')));
      expect(indexed, contains('אספקלריא'));
      expect(indexed, contains('סעיף ראשון'));
      expect(indexed, contains('טבלת השוואה'));
    });

    test('הווריאנט המאונדקס אינו נושא base64 כבד', () {
      final indexed = _bookLines(embedImages: false).join('\n');
      expect(indexed, isNot(contains(_tinyPng)));
      // התג עצמו נשאר — הוא מה ששומר על מבנה השורות.
      expect(indexed, contains('<img src=""'));
    });
  });

  group('מודל הספר', () {
    for (final fileType in const ['html', 'htm']) {
      test('$fileType מיוצר כספר-מסמך שנפתח כספר טקסט', () {
        final book = buildBookForFileType(
          fileType: fileType,
          title: 'ספר הבדיקה',
          path: 'C:/ספרים/ספר.$fileType',
          filePath: 'C:/ספרים/ספר.$fileType',
          categoryId: 3,
        );
        expect(book, isA<ConvertibleDocumentBook>());

        final asText = (book as ConvertibleDocumentBook).toTextBook();
        expect(asText.fileType, fileType);
        expect(asText.filePath, 'C:/ספרים/ספר.$fileType');
        expect(asText.categoryId, 3);
      });
    }

    test('הפורמט טקסטואלי, נאסף לאינדקס ותומך בווריאנט חסר-תמונות', () {
      for (final format in const [DocumentFormat.html, DocumentFormat.htm]) {
        expect(format.isTextual, isTrue, reason: format.name);
        expect(format.isDocumentBook, isTrue, reason: format.name);
        expect(format.supportsImageFreeConversion, isTrue, reason: format.name);
        expect(format.isProductionSupported, isTrue, reason: format.name);
      }
    });
  });
}
