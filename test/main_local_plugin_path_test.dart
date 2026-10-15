import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/main.dart';

void main() {
  group('resolveLocalPluginPathForTesting', () {
    test('מחזיר נתיב Windows גולמי כפי שהוא', () {
      expect(
        resolveLocalPluginPathForTesting(
          r'C:\Users\Foo\Downloads\my plugin.otzplugin',
        ),
        r'C:\Users\Foo\Downloads\my plugin.otzplugin',
      );
    });

    test('מחלץ file:// URI לנתיב מקומי ומפענח רווחים', () {
      // Uri.toFilePath() תלוי-פלטפורמה (Linux מחזיר /, Windows מחזיר \),
      // אז בודקים רק שהתוצאה היא נתיב קובץ, לא URI, ובלי קידוד.
      final result = resolveLocalPluginPathForTesting(
        'file:///home/user/my%20plugin.otzplugin',
      );

      expect(result, isNotNull);
      expect(result, isNot(startsWith('file:')));
      expect(result, contains('my plugin.otzplugin'));
      expect(result, isNot(contains('%20')));
    });

    test('מחזיר null עבור ארגומנט שאינו ‎.otzplugin', () {
      expect(resolveLocalPluginPathForTesting('/home/user/book.pdf'), isNull);
      expect(
        resolveLocalPluginPathForTesting('file:///home/user/book.pdf'),
        isNull,
      );
      expect(resolveLocalPluginPathForTesting(''), isNull);
    });

    test('לא רגיש לאותיות גדולות/קטנות בסיומת', () {
      expect(
        resolveLocalPluginPathForTesting(r'C:\foo\BAR.OTZPLUGIN'),
        r'C:\foo\BAR.OTZPLUGIN',
      );
    });

    test('file:// URI לא תקין נופל בחזרה לבדיקת הסיומת המקורית', () {
      // הקלט אינו URI חוקי אבל מסתיים ב-.otzplugin — נשמר כפי שהוא.
      const malformed = 'file://[invalid.otzplugin';
      expect(
        resolveLocalPluginPathForTesting(malformed),
        malformed,
      );
    });
  });
}
