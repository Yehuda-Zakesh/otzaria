import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// תווית הריחוף של פס הגלילה לפריט [item]: הכתובת של שורתו הראשונה.
String readingScrollbarLabel(TextBookLoaded state, int item) {
  final layout = readingLayoutOf(state);
  final line = item >= 0 && item < layout.itemCount
      ? layout.firstLineOf(item)
      : item;
  return addBookTitleToRef(
    refFromTocList(line, state.tableOfContents),
    state.book.title,
  );
}
