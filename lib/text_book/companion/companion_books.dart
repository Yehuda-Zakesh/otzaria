/// A companion book opens beside its primary book and follows it. It is not a
/// commentary on the primary, so it never joins its commentators.
library;

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

/// Primary book title to companion book title.
const Map<String, String> kCompanionBookTitles = {'משנה ברורה': 'ביאור הלכה'};

/// Whether a primary book opens with its companion: the toolbar toggle's last
/// choice.
const String kShowCompanionBookKey = 'key-show-companion-book';

bool get showCompanionBookByDefault =>
    Settings.getValue<bool>(kShowCompanionBookKey) ?? true;

/// The primary book's share of the split tab; the companion takes a third.
const double kPrimaryPaneShare = 2 / 3;

Future<void> setShowCompanionBookByDefault(bool value) =>
    Settings.setValue<bool>(kShowCompanionBookKey, value);

/// The companion title of [book], or `null` when it has none.
String? companionTitleOf(TextBook book) =>
    book.source.isOfficial ? kCompanionBookTitles[book.title] : null;

/// Whether [pane] is the companion of [primary].
bool isCompanionOf(OpenedTab pane, TextBookTab primary) {
  final title = companionTitleOf(primary.book);
  return title != null &&
      pane is TextBookTab &&
      pane.book.source.isOfficial &&
      pane.book.title == title;
}

/// The companion pane open beside [primary] in [tabs], or `null`.
TextBookTab? openCompanionPane(List<OpenedTab> tabs, TextBookTab primary) {
  for (final tab in tabs) {
    if (tab is! CombinedTab) continue;
    final sibling = tab.sibling(primary);
    if (sibling != null && isCompanionOf(sibling, primary)) {
      return sibling as TextBookTab;
    }
  }
  return null;
}

/// The primary and companion panes of [tab], when it is such a pair.
({TextBookTab primary, TextBookTab companion})? companionPairOf(OpenedTab tab) {
  if (tab is! CombinedTab) return null;
  for (final (primary, companion) in [
    (tab.rightTab, tab.leftTab),
    (tab.leftTab, tab.rightTab),
  ]) {
    if (primary is TextBookTab && isCompanionOf(companion, primary)) {
      return (primary: primary, companion: companion as TextBookTab);
    }
  }
  return null;
}

/// A new tab of the companion of [primary], or `null` when it has none or the
/// companion is not in the library.
Future<TextBookTab?> createCompanionTab(TextBookTab primary) async {
  final title = companionTitleOf(primary.book);
  if (title == null) return null;
  final library = await DataRepository.instance.library;
  final book = library
      .getAllBooks()
      .whereType<TextBook>()
      .where(
        (book) => book.title == title && book.source.isOfficial,
      )
      .firstOrNull;
  if (book == null) return null;
  // The companion starts at the top; the sync moves it to the primary's place.
  return TextBookTab(book: book, index: 0);
}

/// The tab to add when the user opens [tab]: the tab itself, or a split of it
/// with its companion when it has one and the user keeps companions open.
Future<OpenedTab> withCompanionPane(OpenedTab tab) async {
  if (tab is! TextBookTab || companionTitleOf(tab.book) == null) return tab;
  try {
    if (!showCompanionBookByDefault) return tab;
    final companion = await createCompanionTab(tab);
    if (companion == null) return tab;
    return CombinedTab(
      rightTab: tab,
      leftTab: companion,
      splitRatio: kPrimaryPaneShare,
    );
  } catch (_) {
    // The library is not loaded (tests, early startup): open the book alone.
    return tab;
  }
}
