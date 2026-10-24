/// תפקיד חלון אחד, כפי שנחשף ב-`AppWindowScope.roleOf`: החלון הראשי
/// ([AppWindowRole.main]) או חלון Dart ([AppWindowRole.view]).
class AppWindowRole {
  const AppWindowRole({
    required this.isPrimaryView,
    this.openedWithTab = false,
    this.isViewWindow = false,
  });

  /// חלון Dart באותו isolate עם החלון הראשי (ריבוי תצוגות).
  const AppWindowRole.view({bool openedWithTab = false})
    : this(
        isPrimaryView: false,
        openedWithTab: openedWithTab,
        isViewWindow: true,
      );

  /// החלון הראשי, שה-runner יצר.
  static const AppWindowRole main = AppWindowRole(isPrimaryView: true);

  /// האם זה החלון הראשי ולא חלון שנפתח מתוכו.
  final bool isPrimaryView;

  /// האם החלון נפתח עם כרטיסיה שהועברה אליו, כלומר ישר למסך הקריאה.
  final bool openedWithTab;

  /// חלון Dart ולא חלון של ה-runner: מסגרת משלו (`AppVirtualWindowFrame`), ובלי
  /// ה-singletons של החלון הראשי (`windowManager`, חשיפת ה-splash, ה-listener).
  final bool isViewWindow;

  @override
  bool operator ==(Object other) =>
      other is AppWindowRole &&
      other.isPrimaryView == isPrimaryView &&
      other.openedWithTab == openedWithTab &&
      other.isViewWindow == isViewWindow;

  @override
  int get hashCode => Object.hash(isPrimaryView, openedWithTab, isViewWindow);
}
