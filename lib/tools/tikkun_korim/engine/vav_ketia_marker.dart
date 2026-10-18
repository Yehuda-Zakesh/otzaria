import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// מסמן את וי״ו דשלום במקומה, בלי לשנות את הכתיב או את מידות העימוד.
List<TikkunToken> markVavKetiaWords(
  List<TikkunToken> tokens,
  String bookName,
  TikkunTradition tradition,
) {
  if (bookName != 'במדבר') return tokens;
  var chapter = 0;
  var verse = 0;
  final marked = <TikkunToken>[];
  for (final token in tokens) {
    if (token.type == TikkunTokenType.chapterBreak) {
      chapter = token.chapterNum!;
      verse = 0;
    }
    if (token.type == TikkunTokenType.verseBreak) verse = token.verseNum!;
    marked.add(
      chapter == 25 &&
              verse == 12 &&
              token.isWord &&
              stripNikud(token.value!) == 'שלום'
          ? TikkunToken.word(token.value!, vavKetiaTradition: tradition)
          : token,
    );
  }
  return marked;
}
