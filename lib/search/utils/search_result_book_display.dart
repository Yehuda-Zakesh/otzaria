import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_display/text_display_exports.dart';

/// מה שתצוגת ספר בעיון פותרת מעבר למדיניות הגלובלית: שכבת התנ"ך וההגדרות
/// השמורות לספר. כך תקציר תוצאת חיפוש מוצג כמו גוף הספר.
class SearchResultBookDisplay {
  final bool isTanach;
  final TextDisplayLayer bookLayer;

  const SearchResultBookDisplay({
    required this.isTanach,
    required this.bookLayer,
  });

  static final SearchResultBookDisplay general = SearchResultBookDisplay(
    isTanach: false,
    bookLayer: TextDisplayLayer.empty,
  );

  static Future<SearchResultBookDisplay> load(
    Book book, {
    required bool perBookSettingsEnabled,
  }) async {
    final isTanach = await FileSystemData.instance.isTanachBook(
      book.title,
      categoryId: book.categoryId,
      fileType: book.fileType,
    );
    final perBookSettings = perBookSettingsEnabled && book is TextBook
        ? await TextBookPerBookSettings.load(book)
        : null;
    return SearchResultBookDisplay(
      isTanach: isTanach,
      bookLayer:
          perBookSettings?.effectiveDisplayLayer ?? TextDisplayLayer.empty,
    );
  }

  TextDisplayProfile profile(TextDisplayPolicy policy) =>
      TextDisplayResolver.resolve(
        slot: TextDisplaySlot.root,
        layers: [
          bookLayer,
          ...policy.layersFor(isTanach: isTanach),
        ],
      );
}
