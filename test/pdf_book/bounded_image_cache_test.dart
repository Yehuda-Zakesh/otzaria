import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/bounded_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 10x10 פיקסלים = 400 בתים.
  Future<ui.Image> image10() => createTestImage(width: 10, height: 10);

  test('lookup מחזיר עותק שהקורא משחרר בלי לפגוע במטמון', () async {
    final cache = BoundedImageCache<int>(maxBytes: 1000);
    final source = await image10();
    cache.put(1, source);
    source.dispose();

    final first = cache.lookup(1)!;
    first.dispose();
    final second = cache.lookup(1);

    expect(second, isNotNull);
    expect(second!.debugDisposed, isFalse);
    second.dispose();
    cache.dispose();
  });

  test('חריגה מהתקרה זורקת את מה שנעשה בו שימוש לפני הכל', () async {
    final cache = BoundedImageCache<int>(maxBytes: 1000);
    final source = await image10();
    cache.put(1, source);
    cache.put(2, source);
    cache.lookup(1)!.dispose(); // 1 הופך לאחרון בשימוש
    cache.put(3, source);

    expect(cache.length, 2);
    expect(cache.bytes, 800);
    expect(cache.lookup(2), isNull);
    final one = cache.lookup(1)!;
    final three = cache.lookup(3)!;
    one.dispose();
    three.dispose();
    source.dispose();
    cache.dispose();
  });

  test('תמונה יחידה שחורגת מהתקרה נשמרת', () async {
    final cache = BoundedImageCache<int>(maxBytes: 100);
    final source = await image10();
    cache.put(1, source);
    source.dispose();

    expect(cache.length, 1);
    cache.lookup(1)!.dispose();
    cache.dispose();
  });

  test('put חוזר לאותו מפתח מחליף בלי לספור פעמיים', () async {
    final cache = BoundedImageCache<int>(maxBytes: 1000);
    final source = await image10();
    cache.put(1, source);
    cache.put(1, source);
    source.dispose();

    expect(cache.length, 1);
    expect(cache.bytes, 400);
    cache.dispose();
  });

  test('אחרי dispose המטמון ריק ו-put אינו שומר', () async {
    final cache = BoundedImageCache<int>(maxBytes: 1000);
    final source = await image10();
    cache.put(1, source);
    cache.dispose();
    cache.put(2, source);
    source.dispose();

    expect(cache.length, 0);
    expect(cache.bytes, 0);
  });

  test('put עם דור שקדם ל-clear אינו נשמר', () async {
    final cache = BoundedImageCache<int>(maxBytes: 1000);
    final source = await image10();
    final generation = cache.generation;
    cache.clear();
    cache.put(1, source, generation: generation);
    cache.put(2, source, generation: cache.generation);
    source.dispose();

    expect(cache.lookup(1), isNull);
    cache.lookup(2)!.dispose();
    cache.dispose();
  });
}
