import 'dart:collection';
import 'dart:ui' as ui;

/// מטמון תמונות המוגבל בסך הבתים; התמונה שנעשה בה שימוש לפני הכל נזרקת ראשונה.
///
/// המטמון מחזיק עותק ([ui.Image.clone]) משלו, ולכן הקורא משחרר את התמונות
/// שלו בלי תלות במטמון, ותמונה שנזרקה לא נעלמת ממסך שמציג אותה.
class BoundedImageCache<K> {
  BoundedImageCache({required this.maxBytes});

  final int maxBytes;
  final LinkedHashMap<K, ui.Image> _images = LinkedHashMap<K, ui.Image>();
  int _bytes = 0;
  int _generation = 0;
  bool _disposed = false;

  int get length => _images.length;
  int get bytes => _bytes;

  /// עולה בכל [clear]; [put] עם דור ישן מתעלם מהתמונה.
  int get generation => _generation;

  /// עותק של התמונה ששמורה תחת [key], שהקורא אחראי לשחרר; null אם אין.
  ui.Image? lookup(K key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image;
    return image.clone();
  }

  /// שומר עותק של [image] תחת [key]. התמונה עצמה נשארת באחריות הקורא.
  void put(K key, ui.Image image, {int? generation}) {
    if (_disposed) return;
    if (generation != null && generation != _generation) return;
    _remove(key);
    _images[key] = image.clone();
    _bytes += _sizeOf(image);
    // תמונה יחידה שחורגת מהתקרה נשמרת בכל זאת.
    while (_bytes > maxBytes && _images.length > 1) {
      _remove(_images.keys.first);
    }
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void clear() {
    _generation++;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }

  void _remove(K key) {
    final image = _images.remove(key);
    if (image == null) return;
    _bytes -= _sizeOf(image);
    image.dispose();
  }

  static int _sizeOf(ui.Image image) => image.width * image.height * 4;
}
