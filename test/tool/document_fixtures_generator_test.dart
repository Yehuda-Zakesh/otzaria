// שומר על המחולל שב-`tool/generate_document_fixtures.dart` — כל פורמט שהוא
// מייצר חייב להיפתח בממיר, וכל מקרה-קצה חייב להיכשל בדיוק כמתוכנן.
//
// הרגרסיה שהבדיקה מונעת: היו שני בוני CFB, אחד במחולל ואחד בבדיקות. תיקון
// במבנה עץ הספרייה הוחל רק על אחד, והמחולל ייצר קבצים שהקורא דוחה בצדק —
// כלומר קורפוס הבדיקה כולו הפך חסר-ערך בשקט. עכשיו יש בונה אחד, והבדיקה
// כאן מריצה את המחולל ומאמתת את הפלט שלו מקצה לקצה.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;

import '../../tool/generate_document_fixtures.dart';

/// הפורמטים שהמחולל מייצר ואמורים להיפתח, עם מילה שחייבת להופיע בפלט.
const _expectedContent = {
  'basic.docx': 'שלום עולם',
  'basic.docm': 'מאקרו',
  'basic.dotx': 'תבנית',
  'basic.dotm': 'מאקרו',
  'advanced.docx': 'פרק ראשון',
  'advanced.dotx': 'פרק ראשון',
  'basic.odt': 'שלום עולם',
  'advanced.odt': 'פרק ראשון',
  'basic_utf8.rtf': 'שלום עולם',
  'hebrew_cp1255.rtf': 'שלום עולם',
  'unicode_escapes.rtf': 'שלום עולם',
  'advanced.rtf': 'פרק ראשון',
  'basic.doc': 'שלום עולם',
  'basic.dot': 'שלום עולם',
  'hebrew_legacy.doc': 'בדיקת עברית',
  'advanced.doc': 'פרק ראשון',
  'word_binary.wbk': 'שלום עולם',
  'ooxml_like.wbk': 'שלום עולם',
  'flat_opc.xml': 'שלום עולם',
  'wordml_2003.xml': 'פסקה מודגשת',
  'basic.html': 'שלום עולם',
  'advanced.html': 'פרק ראשון',
  'hebrew_cp1255.htm': 'שלום עולם',
};

/// מה ש**אסור** שיופיע בפלט. קובץ HTML הוא הפורמט היחיד שהמשתמש מוריד
/// מהאינטרנט כדבר שבשגרה, ולכן חוזה האבטחה שלו נבדק מקצה לקצה ולא רק ביחידה.
const _forbiddenContent = {
  'advanced.html': [
    'alert', // <script>
    'onload', // מטפל אירועים
    'javascript:', // סכימת קישור מסוכנת
    'otzaria://', // סכימה שמורה לשימוש הפנימי של התוכנה
    'tracker.example', // תמונה מהרשת
    'evil.example', // iframe
    'טקסט מוסתר',
    'transform', // עיצוב שהקורא אינו מכיר — הצהרה מתה
    'position:', //
  ],
};

/// מה ש**חייב** לשרוד: כל מבנה שמנוע התצוגה של אוצריא יודע להציג. הרגרסיה
/// שזה מונע היא מסנן שמהדק יתר על המידה, ואז ספר שעוצב כהלכה מגיע קירח.
const _requiredContent = {
  'advanced.html': [
    '<sup class="footnote-marker">', // מנגנון הערות השוליים
    '<i class="footnote">', //
    '<ruby>', // פירוש מעל מילה
    '<blockquote>', //
    '<details>', // קטע מתקפל, בשורה אחת
    '<hr ', // קו מפריד מעוצב
    'border: 1px solid #8b0000', // תיבה ממוסגרת
    'book://', // קישור לספר אחר
    'width="24"', // מידות תמונה
    'data:image/png;base64,', // תמונה מוטמעת
  ],
};

/// מקרי הקצה והחריגה המדויקת שכל אחד מהם חייב לזרוק.
const _expectedFailures = {
  'corrupted.docx': CorruptedDocumentException,
  'corrupted.odt': CorruptedDocumentException,
  'corrupted.doc': CorruptedDocumentException,
  'encrypted.doc': EncryptedDocumentException,
  'fake.docx': CorruptedDocumentException,
  'fake.odt': CorruptedDocumentException,
  'invalid.wbk': UnsupportedDocumentFormatException,
  'not_word.xml': UnsupportedDocumentFormatException,
  // חבילת ZIP בסיומת .html: פענוח הבייטים שלה כטקסט היה מייצר ג'יבריש
  // עברי שנראה כספר תקין לגמרי.
  'fake.html': UnsupportedDocumentFormatException,
};

/// קבצים תקינים אך חסרי תוכן — מסמך ריק אינו כשל (§60).
const _expectedEmpty = {
  'empty.docx',
  'empty.rtf',
  'corrupted.rtf',
  'empty.html',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('fixture-generator-');
    // קוראים ל-`buildFixtureCorpus` ישירות ולא מריצים את הסקריפט כתת-תהליך:
    // הבדיקה מהירה, וכשל מצביע על הפונקציה עצמה ולא על שרשרת ההרצה.
    buildFixtureCorpus().forEach((name, bytes) {
      File(p.join(tempDir.path, name)).writeAsBytesSync(bytes);
    });
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // נעילת קובץ ב-Windows אינה מעניינה של הבדיקה.
    }
  });

  File fixture(String name) => File(p.join(tempDir.path, name));

  test('המחולל מייצר את כל הקבצים שהבדיקות מצפות להם', () {
    final produced = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toSet();

    expect(
      produced,
      containsAll([
        ..._expectedContent.keys,
        ..._expectedFailures.keys,
        ..._expectedEmpty,
      ]),
    );
  });

  group('פורמטים תקינים נפתחים עם תוכן', () {
    for (final entry in _expectedContent.entries) {
      test(entry.key, () async {
        final file = fixture(entry.key);
        final format = documentFormatFromExtension(entry.key)!;

        final text = await readFileBackedBookText(
          file,
          format.extension,
          'ספר',
        );

        expect(text, isNotNull);
        expect(text, startsWith('<h1>ספר</h1>'));
        expect(
          text,
          contains(entry.value),
          reason: 'התוכן שהמחולל כתב אינו מגיע לפלט הממיר',
        );
      });
    }
  });

  group('חוזה האבטחה — מה שאסור שיגיע לגוף הספר', () {
    for (final entry in _forbiddenContent.entries) {
      test(entry.key, () async {
        final format = documentFormatFromExtension(entry.key)!;
        final text = await readFileBackedBookText(
          fixture(entry.key),
          format.extension,
          'ספר',
        );
        for (final forbidden in entry.value) {
          expect(text, isNot(contains(forbidden)), reason: forbidden);
        }
      });
    }
  });

  group('חוזה התצוגה — מה שחייב לשרוד את ההמרה', () {
    for (final entry in _requiredContent.entries) {
      test(entry.key, () async {
        final format = documentFormatFromExtension(entry.key)!;
        final text = await readFileBackedBookText(
          fixture(entry.key),
          format.extension,
          'ספר',
        );
        for (final required in entry.value) {
          expect(text, contains(required), reason: required);
        }
      });
    }
  });

  group('מקרי קצה נכשלים בחריגה המדויקת', () {
    for (final entry in _expectedFailures.entries) {
      test(entry.key, () async {
        final format = documentFormatFromExtension(entry.key)!;

        await expectLater(
          readFileBackedBookText(fixture(entry.key), format.extension, 'ספר'),
          throwsA(isA<DocumentConversionException>()),
        );

        // בדיקת הטיפוס המדויק: "פגום" ו"מוצפן" מובילים לטיפול שונה ב-UI.
        Object? thrown;
        try {
          await readFileBackedBookText(
            fixture(entry.key),
            format.extension,
            'ספר',
          );
        } catch (e) {
          thrown = e;
        }
        expect(thrown.runtimeType, entry.value);
      });
    }
  });

  test('מסמך תקין אך ריק מחזיר כותרת בלבד ואינו נכשל', () async {
    for (final name in _expectedEmpty) {
      final format = documentFormatFromExtension(name)!;
      final text = await readFileBackedBookText(
        fixture(name),
        format.extension,
        'ספר',
      );
      expect(text, isNotNull, reason: name);
      expect(text!.split('\n').first, '<h1>ספר</h1>', reason: name);
    }
  });

  test('מסמכי DOC בינאריים מכילים piece table אמיתי', () async {
    // ההגנה המרכזית מפני חזרת הבאג: קובץ שהוא רק חתימת OLE + טקסט גולמי
    // נדחה בצדק, ולכן חייב להיות כאן מבנה מלא ולא stub.
    final text = await readFileBackedBookText(
      fixture('hebrew_legacy.doc'),
      'doc',
      'ספר',
    );

    // קידוד מעורב: קטע דחוס (אנגלית) וקטע UTF-16 (עברית) באותו מסמך.
    expect(text, contains('Otzaria'));
    expect(text, contains('בדיקת עברית'));
    expect(text, isNot(contains('�')));
  });
}
