// לתחזוקת מטרות הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:flutter/widgets.dart';

final List<GlobalKey> tourMainNavigationTargetKeys = List<GlobalKey>.generate(
  6,
  (index) => GlobalKey(debugLabel: 'tour_main_navigation_$index'),
);

final List<GlobalKey> tourMainNavigationItemTargetKeys =
    List<GlobalKey>.generate(
      6,
      (index) => GlobalKey(debugLabel: 'tour_main_navigation_item_$index'),
    );

final GlobalKey tourReadingScreenTargetKey = GlobalKey(
  debugLabel: 'tour_reading_screen_target',
);
final GlobalKey tourReadingTabsTargetKey = GlobalKey(
  debugLabel: 'tour_reading_tabs_target',
);

/// עמודת הכרטיסיות האנכית. מפתח נפרד מ-[tourReadingTabsTargetKey]: העמודה
/// נשארת בעץ ברוחב 0 גם במצב "למעלה", ומפתח משותף היה מתנגש בין השתיים.
final GlobalKey tourReadingTabsSideTargetKey = GlobalKey(
  debugLabel: 'tour_reading_tabs_side_target',
);
final GlobalKey tourReadingSettingsButtonTargetKey = GlobalKey(
  debugLabel: 'tour_reading_settings_button_target',
);
final GlobalKey tourFindRefDialogTargetKey = GlobalKey(
  debugLabel: 'tour_find_ref_dialog_target',
);

final GlobalKey tourSearchDialogTargetKey = GlobalKey(
  debugLabel: 'tour_search_dialog_target',
);

final Map<int, GlobalKey> tourSettingsTabTargetKeys = {
  0: GlobalKey(debugLabel: 'tour_settings_design_tab_target'),
};

final GlobalKey tourTitleBarHistoryButtonTargetKey = GlobalKey(
  debugLabel: 'tour_title_bar_history_button_target',
);
final GlobalKey tourTitleBarBookmarkButtonTargetKey = GlobalKey(
  debugLabel: 'tour_title_bar_bookmark_button_target',
);

/// פאנל משגר הכלים. נשאר בעץ גם כשהוא סגור, ולכן הריבוע נלקח רק כשהוא פתוח.
final GlobalKey tourToolsLauncherPanelTargetKey = GlobalKey(
  debugLabel: 'tour_tools_launcher_panel_target',
);

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
