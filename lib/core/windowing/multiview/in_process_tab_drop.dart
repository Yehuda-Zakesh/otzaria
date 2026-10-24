import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

/// ממיר נקודת מסך לחלון [hwnd] (null — החלון הראשי); ראו
/// [RunnerWindowChannel.screenToClient].
typedef ScreenToClient =
    Future<Offset?> Function(
      int x,
      int y,
      double devicePixelRatio, {
      int? hwnd,
    });

/// חלון אחר בתהליך, כפי שמוצג ב"העבר לחלון קיים" ובאזהרת השולחן.
@immutable
class WindowPeer {
  const WindowPeer({
    required this.slot,
    required this.title,
    required this.tabCount,
    this.isOwner = false,
    this.isVisible = true,
    this.activeWorkspaceId,
  });

  /// משבצת הסשן: 1 לראשי, ומ-2 לחלונות Dart.
  final int slot;

  /// כותרת לתצוגה בתפריט — בדרך כלל שם הכרטיסיה הפעילה באותו חלון.
  final String title;

  final int tabCount;

  /// האם זה החלון הראשי.
  final bool isOwner;

  /// ⚠️ ראשי שנסגר מוסתר ולא נהרס; כרטיסיה שתועבר אליו הייתה נעלמת.
  final bool isVisible;

  /// השולחן שהחלון עומד עליו, אם בחר אחד.
  final String? activeWorkspaceId;

  @override
  bool operator ==(Object other) =>
      other is WindowPeer &&
      other.slot == slot &&
      other.title == title &&
      other.tabCount == tabCount &&
      other.isOwner == isOwner &&
      other.isVisible == isVisible &&
      other.activeWorkspaceId == activeWorkspaceId;

  @override
  int get hashCode =>
      Object.hash(slot, title, tabCount, isOwner, isVisible, activeWorkspaceId);
}

/// חלון אחד באותו isolate שכרטיסיה נגררת יכולה לנחות בו.
class InProcessTabDropTarget {
  InProcessTabDropTarget({
    required this.dragState,
    required this.devicePixelRatio,
    required this.receive,
    this.describe,
  });

  /// החיווי ומיקום ההכנסה של רצועת הכרטיסיות של החלון.
  final ExternalTabDragState dragState;
  final double Function() devicePixelRatio;

  /// מוסיף את [tab] בחלון, ב-[index] כשניתן. false — לא נקלטה.
  final bool Function(OpenedTab tab, int? index) receive;

  /// מה שמוצג על החלון בתפריט "העבר לחלון קיים"; null — כותרת כללית.
  final InProcessWindowInfo Function()? describe;
}

/// תיאור חלון לתפריט ולאזהרת השולחן.
typedef InProcessWindowInfo = ({
  String title,
  int tabCount,
  String? activeWorkspaceId,
});

/// העברת כרטיסיות בין חלונות התהליך, ישירות בין ה-`TabsBloc` שלהם.
/// "משבצת" כאן היא משבצת הסשן: 1 לראשי, ומ-2 לחלונות Dart.
class InProcessTabDrops {
  InProcessTabDrops({
    ViewWindowRegistry? registry,
    ScreenToClient? screenToClient,
  }) : _registryOverride = registry,
       _screenToClient =
           screenToClient ?? const RunnerWindowChannel().screenToClient;

  static final InProcessTabDrops instance = InProcessTabDrops();

  @visibleForTesting
  static InProcessTabDrops? debugOverride;

  /// [instance], או ההחלפה של הבדיקות.
  static InProcessTabDrops get current => debugOverride ?? instance;

  static const int mainSlot = 1;

  final ViewWindowRegistry? _registryOverride;
  final ScreenToClient _screenToClient;
  final Map<AppWindowId, InProcessTabDropTarget> _targets = {};

  /// החלון הראשי שנסגר מוסתר ולא נהרס, ואינו יעד עד שיוצג שוב.
  bool _mainShown = true;

  bool get isMainShown => _mainShown;

  void setMainShown(bool shown) => _mainShown = shown;

  ViewWindowRegistry get _registry =>
      _registryOverride ?? ViewWindowRegistry.instance;

  void register(AppWindowId id, InProcessTabDropTarget target) =>
      _targets[id] = target;

  /// רק אם [target] עדיין הרשום: עץ שנבנה מחדש נרשם לפני שהישן מתפרק.
  void unregister(AppWindowId id, InProcessTabDropTarget target) {
    if (identical(_targets[id], target)) _targets.remove(id);
  }

  ViewWindowEntry? _entryOf(AppWindowId id) {
    for (final entry in _registry.windows) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  AppWindowId? _idOf(int slot) {
    if (slot == mainSlot) return AppWindowId.primary;
    for (final entry in _registry.windows) {
      if (entry.slot == slot) return entry.id;
    }
    return null;
  }

  /// המשבצת של החלון [id], או null לחלון שאינו פתוח.
  int? slotOf(AppWindowId id) =>
      id == AppWindowId.primary ? mainSlot : _entryOf(id)?.slot;

  /// ה-HWND שנשלח ל-runner עבור [id]; null לראשי, שהוא ברירת המחדל שם.
  int? hwndOf(AppWindowId id) =>
      id == AppWindowId.primary ? null : _entryOf(id)?.handle.hwnd;

  /// החלון שתחת הסמן: חלון Dart לפי ה-HWND שלו, הראשי לפי המשבצת שה-runner
  /// מדווח עליו בלבד; null — שולחן העבודה או תוכנה אחרת.
  int? resolve({int? hwnd, int? runnerSlot}) {
    if (hwnd != null) {
      for (final entry in _registry.windows) {
        if (entry.handle.hwnd == hwnd) return entry.slot;
      }
    }
    return runnerSlot != null ? mainSlot : null;
  }

  InProcessTabDropTarget? _targetOf(int slot) {
    final id = _idOf(slot);
    return id == null ? null : _targets[id];
  }

  /// מדליק את החיווי בחלון [slot] ומחזיר את מיקום ההכנסה ברצועה שלו.
  Future<int?> notifyDragOver(int slot, int x, int y, String title) async {
    final target = _targetOf(slot);
    final id = _idOf(slot);
    if (target == null || id == null) return null;
    final local = await _screenToClient(
      x,
      y,
      target.devicePixelRatio(),
      hwnd: hwndOf(id),
    );
    if (local == null || !identical(_targetOf(slot), target)) return null;
    target.dragState.drag.value = ExternalTabDrag(title: title, local: local);
    // הרצועה מחשבת את מיקום ההכנסה בתגובה לעדכון, ולכן הוא נקרא אחריו.
    return target.dragState.dropIndex.value;
  }

  void notifyDragLeave(int slot) {
    final target = _targetOf(slot);
    if (target != null) target.dragState.drag.value = null;
  }

  /// החלונות האחרים מלבד [self], הראשי ראשון ואחריו לפי משבצת. חלון שעוד
  /// לא בנה עץ אינו ברשימה: אין לו יעד לקלוט.
  List<WindowPeer> peers(AppWindowId self) {
    final views = [..._registry.windows]
      ..sort((a, b) => a.slot.compareTo(b.slot));
    return [
      ?_peer(self, AppWindowId.primary, mainSlot, isVisible: _mainShown),
      for (final entry in views)
        if (!entry.isClosing) ?_peer(self, entry.id, entry.slot),
    ];
  }

  WindowPeer? _peer(
    AppWindowId self,
    AppWindowId id,
    int slot, {
    bool isVisible = true,
  }) {
    final target = _targets[id];
    if (id == self || target == null) return null;
    final info = target.describe?.call();
    return WindowPeer(
      slot: slot,
      title: info?.title ?? 'חלון $slot',
      tabCount: info?.tabCount ?? 0,
      isOwner: id == AppWindowId.primary,
      isVisible: isVisible,
      activeWorkspaceId: info?.activeWorkspaceId,
    );
  }

  /// היעדים של "העבר לחלון קיים" מתוך [self]: מוצגים על המסך בלבד.
  List<WindowPeer> transferTargets(AppWindowId self) => [
    for (final peer in peers(self))
      if (peer.isVisible) peer,
  ];

  /// האם חלון מוצג אחר מלבד [self] עומד על השולחן [workspaceId].
  bool isWorkspaceOpenElsewhere(AppWindowId self, String workspaceId) =>
      transferTargets(self).any((p) => p.activeWorkspaceId == workspaceId);

  /// מעביר עותק של [tab] לחלון [slot]; המקור מסיר את שלו רק אחרי true.
  /// ⚠️ עותק ולא אותו מופע: `RemoveTab` במקור משחרר את הכרטיסיה שלו.
  Future<bool?> sendTabToWindow(int slot, OpenedTab tab, {int? index}) async {
    final target = _targetOf(slot);
    if (target == null) return false;
    // ראשי מוסתר: הכרטיסיה הייתה נעלמת בחלון שאינו על המסך.
    if (slot == mainSlot && !_mainShown) return false;
    // חלון שסגירתו אושרה: הכרטיסיה הייתה נסגרת איתו.
    if (_registry.windows.any((w) => w.slot == slot && w.isClosing)) {
      return false;
    }
    final OpenedTab copy;
    try {
      copy = OpenedTab.fromJson(tab.toTransferJson());
    } catch (e) {
      debugPrint('InProcessTabDrops: failed to copy tab: $e');
      return false;
    }
    if (target.receive(copy, index)) return true;
    copy.dispose();
    return false;
  }
}

/// רושם את החלון שמעליו כיעד להעברה ישירה, ונותן לו מצב גרירה חיצונית משלו.
/// עם ריבוי תצוגות בלבד; הראשי שומר על [ExternalTabDragState.current].
class InProcessTabDropReceiver extends StatefulWidget {
  const InProcessTabDropReceiver({super.key, this.drops, required this.child});

  /// ברירת המחדל היא [InProcessTabDrops.instance].
  final InProcessTabDrops? drops;
  final Widget child;

  @override
  State<InProcessTabDropReceiver> createState() =>
      _InProcessTabDropReceiverState();
}

class _InProcessTabDropReceiverState extends State<InProcessTabDropReceiver> {
  late final AppWindowId _id = AppWindowKeys.of(context).id;
  late final ExternalTabDragState _dragState = _id == AppWindowId.primary
      ? ExternalTabDragState.current
      : ExternalTabDragState();
  late final InProcessTabDropTarget _target = InProcessTabDropTarget(
    dragState: _dragState,
    devicePixelRatio: () => View.maybeOf(context)?.devicePixelRatio ?? 1.0,
    receive: _receive,
    describe: _describe,
  );

  InProcessTabDrops get _drops => widget.drops ?? InProcessTabDrops.instance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drops.register(_id, _target);
  }

  bool _receive(OpenedTab tab, int? index) {
    if (!mounted) return false;
    final tabsBloc = context.read<TabsBloc>();
    // bloc שנסגר זורק על add; false משאיר את הכרטיסיה במקור.
    if (tabsBloc.isClosed) return false;
    if (!tabsBloc.receiveTransferredTab(tab, index: index)) return false;
    _dragState.drag.value = null;
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
    unawaited(_raise());
    return true;
  }

  /// הכרטיסיה הפעילה, מספר הכרטיסיות והשולחן הפעיל.
  InProcessWindowInfo _describe() {
    if (!mounted) {
      return (title: 'חלון ריק', tabCount: 0, activeWorkspaceId: null);
    }
    final tabs = context.read<TabsBloc>().state;
    return (
      title: tabs.currentTab?.title ?? 'חלון ריק',
      tabCount: tabs.tabs.length,
      activeWorkspaceId: context
          .read<WorkspaceBloc?>()
          ?.state
          .activeWorkspaceId,
    );
  }

  /// המשתמש עובר עם הכרטיסיה לחלון היעד.
  Future<void> _raise() async {
    if (_id == AppWindowId.primary) {
      return const RunnerWindowChannel().raiseSelf();
    }
    final scope = context.getInheritedWidgetOfExactType<AppWindowScope>();
    await scope?.controller.focus();
  }

  @override
  void dispose() {
    _drops.unregister(_id, _target);
    if (!identical(_dragState, ExternalTabDragState.current)) {
      _dragState.drag.dispose();
      _dragState.dropIndex.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ExternalTabDragScope(state: _dragState, child: widget.child);
}
