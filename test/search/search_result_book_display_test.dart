import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/search_result_book_display.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

void main() {
  final hideNikudShowInTanach = TextDisplayPolicy.fromLegacy(
    defaultRemoveNikud: true,
    removeNikudFromTanach: false,
    defaultRemovePunctuation: false,
    showTeamim: true,
    replaceHolyNames: false,
    holyNameStyle: HolyNameStyle.kufKuf,
  );

  test('ספר תנ"ך מקבל את החרגת התנ"ך כמו בעיון', () {
    expect(
      SearchResultBookDisplay.general
          .profile(hideNikudShowInTanach)
          .removeNikud,
      isTrue,
    );
    expect(
      SearchResultBookDisplay(
        isTanach: true,
        bookLayer: TextDisplayLayer.empty,
      ).profile(hideNikudShowInTanach).removeNikud,
      isFalse,
    );
  });

  test('הגדרה שנשמרה לספר גוברת על המדיניות הגלובלית', () {
    final display = SearchResultBookDisplay(
      isTanach: false,
      bookLayer: TextDisplayLayer({
        TextDisplaySlot.root: const TextDisplayPatch(
          nikud: MarkVisibility.show,
        ),
      }),
    );
    expect(display.profile(hideNikudShowInTanach).removeNikud, isFalse);
  });
}
