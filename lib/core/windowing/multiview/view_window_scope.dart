import 'package:flutter/widgets.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/app_scope/window_scope_providers.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/core/windowing/window_title_sync.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// בונה את מסלול הסגירה של חלון; ניתן להחלפה בבדיקות.
typedef ViewWindowCloseFlowFactory =
    ViewWindowCloseFlow Function(ViewWindowEntry entry);

/// היקף החלון של חלון Dart: בקר, מפתחות, תפקיד וספקי חלון משלו, בלי
/// `WindowBusHost` (האפיק שייך ל-isolate, ומופע שני היה גונב את הבקשות).
class ViewWindowScope extends StatefulWidget {
  const ViewWindowScope({
    super.key,
    required this.entry,
    this.historyRepository,
    this.closeFlow = _defaultCloseFlow,
    required this.child,
  });

  final ViewWindowEntry entry;

  /// `null` — מופע משל החלון: לפיו ה-HistoryBloc מסנן רק את הכתיבות שלו.
  final HistoryRepository? historyRepository;
  final ViewWindowCloseFlowFactory closeFlow;
  final Widget child;

  /// חלון Dart אינו מריץ עבודה של התהליך ואינו מארח את התוספים שברקע.
  static final ProcessDuties duties = ProcessDuties(
    isProcessOwner: () => false,
    hostsPluginBackground: false,
  );

  static ViewWindowCloseFlow _defaultCloseFlow(ViewWindowEntry entry) =>
      ViewWindowCloseFlow(entry: entry);

  @override
  State<ViewWindowScope> createState() => _ViewWindowScopeState();
}

class _ViewWindowScopeState extends State<ViewWindowScope> {
  late final ViewWindowEntry _entry = widget.entry;
  late final OpenedTab? _initialTab;
  late final ViewWindowCloseFlow _closeFlow = widget.closeFlow(_entry);
  late final HistoryRepository _history =
      widget.historyRepository ?? HistoryRepository();
  late final WindowTitleSync _titleSync = WindowTitleSync(
    setTitle: (title) async => _entry.handle.setTitle(title),
  );
  late final WindowPersistenceBinding _persistence = WindowPersistenceBinding(
    controller: _entry.controller,
    geometry: _entry.controller,
    slot: () => _entry.tabsSession.slot,
    view: _entry.handle.view,
  );
  // נשמר מראש: בסגירה הבקר של החלון כבר עשוי להיות מושמד.
  late final int _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = _entry.handle.view.viewId;
    _initialTab = _entry.takeInitialTab();
    _entry.closeHandler = _close;
    WindowTitleSync.bind(_entry.keys, _titleSync);
    _entry.handle.changes.addListener(_onWindowChanged);
    _onWindowChanged();
  }

  Future<void> _close() => _closeFlow.run();

  void _onWindowChanged() {
    PluginRuntimeDispatcher.instance.setWindowMinimized(
      _entry.handle.isMinimized,
      viewId: _viewId,
    );
    // לא לפי מעבר: ב-WA_INACTIVE החלון עוד ב-foreground, ומעבר שנבלע שם
    // השאיר את הראשי פעיל כשהמשתמש חזר לכאן (ESC סגר תפריט בראשי).
    if (_entry.handle.isActivated && AppWindowKeys.current.id != _entry.id) {
      AppWindowKeys.activateWindow(_entry.id);
    }
    // אין הודעה על הזזה בלבד: מיקום חדש נשמר בשינוי הבא.
    _persistence.scheduleSave();
  }

  @override
  void dispose() {
    _entry.handle.changes.removeListener(_onWindowChanged);
    _persistence.dispose();
    WindowTitleSync.unbind(_entry.keys, _titleSync);
    if (_entry.closeHandler == _close) {
      _entry.closeHandler = null;
    }
    // התוספים שהוצגו בחלון אינם מוצגים עוד; בלי זה היו נשארים רצים.
    PluginRuntimeDispatcher.instance.forgetWindow(_viewId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppWindowScope(
    controller: _entry.controller,
    geometry: _entry.controller,
    keys: _entry.keys,
    role: AppWindowRole.view(openedWithTab: _entry.openedWithTab),
    child: WindowScopeProviders(
      historyRepository: _history,
      initialTab: _initialTab,
      tabsSession: _entry.tabsSession,
      duties: ViewWindowScope.duties,
      initialFullscreen: _entry.handle.isFullscreen,
      child: widget.child,
    ),
  );
}
