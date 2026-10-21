// לתחזוקת מטרות הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';

/// יעדי הסיור המודרך של חלון אחד. פר-חלון, כי שני חלונות ב-isolate משותף
/// היו מתנגשים על אותו GlobalKey.
class TourTargetKeys {
  TourTargetKeys();

  /// מפתחות החלון ש-[context] יושב בו.
  static TourTargetKeys of(BuildContext context) =>
      AppWindowKeys.of(context).tour;

  final List<GlobalKey> mainNavigation = List<GlobalKey>.generate(
    6,
    (index) => GlobalKey(debugLabel: 'tour_main_navigation_$index'),
  );

  final List<GlobalKey> mainNavigationItems = List<GlobalKey>.generate(
    6,
    (index) => GlobalKey(debugLabel: 'tour_main_navigation_item_$index'),
  );

  final GlobalKey readingScreen = GlobalKey(
    debugLabel: 'tour_reading_screen_target',
  );
  final GlobalKey readingTabs = GlobalKey(
    debugLabel: 'tour_reading_tabs_target',
  );

  /// עמודת הכרטיסיות האנכית. מפתח נפרד מ-[readingTabs]: העמודה נשארת בעץ
  /// ברוחב 0 גם במצב "למעלה", ומפתח משותף היה מתנגש בין השתיים.
  final GlobalKey readingTabsSide = GlobalKey(
    debugLabel: 'tour_reading_tabs_side_target',
  );
  final GlobalKey readingSettingsButton = GlobalKey(
    debugLabel: 'tour_reading_settings_button_target',
  );
  final GlobalKey findRefDialog = GlobalKey(
    debugLabel: 'tour_find_ref_dialog_target',
  );
  final GlobalKey searchDialog = GlobalKey(
    debugLabel: 'tour_search_dialog_target',
  );

  final Map<int, GlobalKey> settingsTabs = {
    0: GlobalKey(debugLabel: 'tour_settings_design_tab_target'),
  };

  final GlobalKey titleBarHistoryButton = GlobalKey(
    debugLabel: 'tour_title_bar_history_button_target',
  );
  final GlobalKey titleBarBookmarkButton = GlobalKey(
    debugLabel: 'tour_title_bar_bookmark_button_target',
  );

  /// פאנל משגר הכלים. נשאר בעץ גם כשהוא סגור, ולכן הריבוע נלקח רק כשהוא פתוח.
  final GlobalKey toolsLauncherPanel = GlobalKey(
    debugLabel: 'tour_tools_launcher_panel_target',
  );

  /// חלונית הניווט של טאב הטקסט הפעיל. כל הטאבים חיים בעץ במקביל, ולכן
  /// הטאב הפעיל מפרסם כאן את המפתח שלו (ראו TextBookNavPanelTourTarget).
  GlobalKey? activeTextBookNavPanel;

  // כפתורי סרגל הכלים של ספר טקסט.
  final GlobalKey textBookNavigation = GlobalKey(
    debugLabel: 'text_book_navigation_tour_target',
  );
  final GlobalKey textBookCommentators = GlobalKey(
    debugLabel: 'text_book_commentators_tour_target',
  );
  final GlobalKey textBookBookmark = GlobalKey(
    debugLabel: 'text_book_bookmark_tour_target',
  );
  final GlobalKey textBookSearch = GlobalKey(
    debugLabel: 'text_book_search_tour_target',
  );
  final GlobalKey textBookPrint = GlobalKey(
    debugLabel: 'text_book_print_tour_target',
  );
  final GlobalKey textBookOverflow = GlobalKey(
    debugLabel: 'text_book_overflow_tour_target',
  );
  final GlobalKey textBookOverflowCommentators = GlobalKey(
    debugLabel: 'text_book_overflow_commentators_tour_target',
  );
  final GlobalKey textBookOverflowBookmark = GlobalKey(
    debugLabel: 'text_book_overflow_bookmark_tour_target',
  );
  final GlobalKey textBookOverflowSearch = GlobalKey(
    debugLabel: 'text_book_overflow_search_tour_target',
  );
  final GlobalKey textBookOverflowPrint = GlobalKey(
    debugLabel: 'text_book_overflow_print_tour_target',
  );

  // כפתורי סרגל הכלים של ספר PDF.
  final GlobalKey pdfBookNavigation = GlobalKey(
    debugLabel: 'pdf_book_navigation_tour_target',
  );
  final GlobalKey pdfBookBookmark = GlobalKey(
    debugLabel: 'pdf_book_bookmark_tour_target',
  );
  final GlobalKey pdfBookSearch = GlobalKey(
    debugLabel: 'pdf_book_search_tour_target',
  );
  final GlobalKey pdfBookPrint = GlobalKey(
    debugLabel: 'pdf_book_print_tour_target',
  );
  final GlobalKey pdfBookOverflow = GlobalKey(
    debugLabel: 'pdf_book_overflow_tour_target',
  );
  final GlobalKey pdfBookOverflowBookmark = GlobalKey(
    debugLabel: 'pdf_book_overflow_bookmark_tour_target',
  );
  final GlobalKey pdfBookOverflowSearch = GlobalKey(
    debugLabel: 'pdf_book_overflow_search_tour_target',
  );
  final GlobalKey pdfBookOverflowPrint = GlobalKey(
    debugLabel: 'pdf_book_overflow_print_tour_target',
  );
}

/// האם יעדי הסיור של הטאב שמתחת פעילים. רק היעדים תלויים בו, ולכן מעבר טאב
/// אינו בונה מחדש את מסך הספר כולו.
class TourTargetsScope extends InheritedWidget {
  final bool enabled;

  const TourTargetsScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TourTargetsScope>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(TourTargetsScope oldWidget) =>
      enabled != oldWidget.enabled;
}
