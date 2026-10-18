import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

enum TikkunVavKetia {
  auto('auto'),
  regular('regular'),
  small('small', 0xE140),
  yod('yod', 0xE141),
  short('short', 0xE142),
  split('split', 0xE143),
  splitDiagonal('splitDiagonal', 0xE144),
  splitHigh('splitHigh', 0xE145),
  shortTail('shortTail', 0xE146),
  smallTail('smallTail', 0xE147),
  bridge('bridge', 0xE148),
  bridgeDiagonal('bridgeDiagonal', 0xE149),
  insetDiagonal('insetDiagonal', 0xE14A);

  const TikkunVavKetia(this.id, [this.codePoint]);

  final String id;
  final int? codePoint;

  int? codeFor(TikkunTradition tradition) => this == auto
      ? (tradition == TikkunTradition.yemen ? null : shortTail.codePoint)
      : codePoint;

  static TikkunVavKetia byId(String? id) {
    for (final form in values) {
      if (form.id == id) return form;
    }
    return auto;
  }
}

final _vavKetiaGlyphs = RegExp('[\uE140-\uE14A]');

/// מחזיר תווי גופן פרטיים לווי״ו רגילה בשכבת הטקסט של ה־PDF.
String restoreTikkunVavKetiaText(String text) =>
    text.replaceAll(_vavKetiaGlyphs, 'ו');
