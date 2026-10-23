import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיסיה שיש בה שינויים שלא נשמרו, עם ההודעה שצורפה (אם צורפה).
typedef UnsavedTabEntry = ({OpenedTab tab, String? message});

/// חלוניות התוסף מתוך [tabs] (כולל צדדי כרטיסיה מפוצלת) שיש בהן שינויים
/// שלא נשמרו, לפי [PluginUnsavedChangesRegistry].
List<UnsavedTabEntry> unsavedPluginTabs(
  Iterable<OpenedTab> tabs, {
  PluginUnsavedChangesRegistry? registry,
}) {
  final reg = registry ?? PluginUnsavedChangesRegistry.instance;
  return [
    for (final tab in tabs)
      for (final pane in leafPanes(tab))
        if (pane is ToolTab && pane.isPlugin)
          if (reg.hasUnsavedChanges((
            pluginId: pane.toolId,
            instanceId: pane.instanceId,
          )))
            (
              tab: pane,
              message: reg.messageFor((
                pluginId: pane.toolId,
                instanceId: pane.instanceId,
              )),
            ),
  ];
}

String unsavedCorrectionsMessage(String pluginName) =>
    'תיקוני התוסף ‹$pluginName› עדיין לא נשמרו לטיוטת ההתאוששות.';

/// לשוניות קורא שתיקוני התוסף בהן לא נשמרו לטיוטה גם אחרי ניסיון שמירה.
/// טיוטה שנשמרה אינה אובדת בסגירה, ולכן אינה מוחזרת.
Future<List<UnsavedTabEntry>> unpersistedCorrectionTabs(
  Iterable<OpenedTab> tabs, {
  PluginCorrectionSessionService? service,
}) async {
  final sessions = service ?? PluginCorrectionSessionService.instance;
  final panes = _correctionPanes(tabs);
  if (panes.isEmpty) return const [];
  // כולל סשן שהסתיים (סיום עריכה, השבתה) וטרם נשמר — הוא עדיין בלשונית.
  return [
    for (final state in await sessions.unsavedStates(tabIds: panes.keys))
      (
        tab: panes[state.tabId]!,
        message: unsavedCorrectionsMessage(state.ownerName),
      ),
  ];
}

Map<String, TextBookTab> _correctionPanes(Iterable<OpenedTab> tabs) => {
  for (final tab in tabs)
    for (final pane in leafPanes(tab))
      if (pane is TextBookTab)
        ?PluginCorrectionSessionService.knownTabIdFor(pane): pane,
};

/// תיקונים שלא נשמרו ושאינם שייכים לאף אחת מ-[tabs] — הלשונית שלהם נסגרה.
Future<List<String>> unsavedClosedTabCorrections(
  Iterable<OpenedTab> tabs, {
  PluginCorrectionSessionService? service,
}) async {
  final sessions = service ?? PluginCorrectionSessionService.instance;
  final open = _correctionPanes(tabs).keys.toSet();
  return [
    for (final state in await sessions.unsavedStates())
      if (!open.contains(state.tabId))
        'תיקוני התוסף ‹${state.ownerName}› בספר "${state.bookId}" עדיין לא '
            'נשמרו לטיוטת ההתאוששות.',
  ];
}

const String unsavedChangesDialogTitle = 'שינויים שלא נשמרו';
const String unsavedChangesDialogSubtitle = 'הסגירה תמחק את השינויים שלא נשמרו';
const String unsavedChangesAppCloseSubtitle =
    'סגירת התוכנה תמחק את השינויים שלא נשמרו';
const String unsavedChangesWindowCloseSubtitle =
    'סגירת החלון תמחק את השינויים שלא נשמרו';
const String unsavedChangesCloseAnyway = 'סגור בכל זאת';

/// גוף הדיאלוג: שורה לכל כרטיסיה, ואחריה ההודעה שהתוסף צירף.
String unsavedChangesDialogContent(List<UnsavedTabEntry> entries) {
  final lines = <String>[];
  for (final entry in entries) {
    lines.add('ב"${entry.tab.title}" יש שינויים שלא נשמרו.');
    final message = entry.message;
    if (message != null) lines.add(message);
  }
  return lines.join('\n');
}

/// מאשר סגירה של [tabs]: אם אין בהן שינויים שלא נשמרו מחזיר `true`, אחרת
/// מציג דיאלוג אזהרה ומחזיר את בחירת המשתמש. תיקוני קורא נשמרים קודם לטיוטה.
Future<bool> confirmCloseTabs(
  BuildContext context,
  Iterable<OpenedTab> tabs, {
  String subtitle = unsavedChangesDialogSubtitle,
  PluginCorrectionSessionService? corrections,
  bool includeClosedTabCorrections = false,
  List<String> additionalMessages = const [],
}) async {
  final entries = [
    ...unsavedPluginTabs(tabs),
    ...await unpersistedCorrectionTabs(tabs, service: corrections),
  ];
  final closed = includeClosedTabCorrections
      ? await unsavedClosedTabCorrections(tabs, service: corrections)
      : const <String>[];
  final clean = entries.isEmpty && closed.isEmpty && additionalMessages.isEmpty;
  if (clean || !context.mounted) return clean;
  final confirmed = await showWarningDialog(
    context: context,
    title: unsavedChangesDialogTitle,
    content: [
      if (entries.isNotEmpty) unsavedChangesDialogContent(entries),
      ...closed,
      ...additionalMessages,
    ].join('\n'),
    subtitle: subtitle,
    confirmText: unsavedChangesCloseAnyway,
  );
  return confirmed == true;
}

/// העברת לשונית לחלון אחר סוגרת אותה במקור, ולכן נבדקת כמו סגירה.
Future<bool> confirmTabTransferWithUnsavedChanges(OpenedTab tab) async {
  final context = navigatorKey.currentContext;
  if (context == null) return true;
  return confirmCloseTabs(context, [tab]);
}

Future<bool>? _pendingAppClose;
int _nextProcessQuitRequest = 0;
({String id, List<int> peers, Set<String> accepted})? _preparedProcessQuit;

/// אישור סגירת התוכנה כשיש בכרטיסיות תוסף שינויים שלא נשמרו.
///
/// כמה מאזיני סגירת-חלון (הראשי, ושל העדכון) שואלים כל אחד בנפרד; הבטחה
/// משותפת מבטיחה דיאלוג אחד ותשובה אחת לכולם, גם בלחיצה כפולה על ה-X.
///
/// [window] — החלון שנסגר; `null` — [AppWindowKeys.current]. עם חלונות Dart
/// החלון הפעיל עשוי להיות אחר (סגירה משורת המשימות).
Future<bool> confirmAppCloseWithUnsavedChanges({
  bool allWindows = false,
  AppWindowKeys? window,
}) {
  final pending = _pendingAppClose;
  if (pending != null) return pending;
  final keys = window ?? AppWindowKeys.current;
  final context = keys.navigator.currentContext;
  if (context == null) return Future.value(true);
  final future = allWindows
      ? _confirmAllWindowCorrections(context, keys)
      : confirmCloseTabs(
          context,
          context.read<TabsBloc>().state.tabs,
          subtitle: _closeSubtitle(keys),
          includeClosedTabCorrections: true,
        );
  final shared = future.whenComplete(() => _pendingAppClose = null);
  _pendingAppClose = shared;
  return shared;
}

/// "סגירת החלון" כשנשאר חלון פתוח אחר — באפיק, או חלון Dart שאינו [closing].
/// הראשי אינו נספר: כשחלון Dart נסגר אחרון, הראשי מוסתר.
String _closeSubtitle(AppWindowKeys closing) {
  final others =
      WindowBus.instance.hasOtherWindows ||
      (MultiViewMode.enabled &&
          AppWindowKeys.registered.any(
            (keys) =>
                keys.id != AppWindowId.primary && !identical(keys, closing),
          ));
  return others
      ? unsavedChangesWindowCloseSubtitle
      : unsavedChangesAppCloseSubtitle;
}

Future<bool> _confirmAllWindowCorrections(
  BuildContext context,
  AppWindowKeys keys,
) async {
  final corrections = PluginCorrectionSessionService.instance;
  final requestId =
      '${WindowBus.instance.slot ?? 0}-${DateTime.now().microsecondsSinceEpoch}-${_nextProcessQuitRequest++}';
  if (!corrections.beginProcessQuitPreparation(requestId)) return false;
  final peers = WindowBus.instance.otherRegisteredSlots();
  var retained = false;
  try {
    final replies = await Future.wait([
      for (final slot in peers)
        WindowBus.instance.request(
          slot,
          {
            'type': MultiWindowService.requestPrepareCorrectionQuit,
            'requestId': requestId,
          },
          timeout: MultiWindowService.correctionQuitRequestTimeout,
        ),
    ]);
    final unavailable = replies.any(
      (reply) => reply is! Map || reply['locked'] != true,
    );
    if (unavailable) {
      UiSnack.showError(PluginMessages.correctionQuitUnverified);
      return false;
    }
    final unsaved = await corrections.unsavedStates();
    if (!context.mounted) return false;
    final accepted = {
      for (final state in unsaved)
        jsonEncode([
          WindowBus.instance.slot,
          state.tabId,
          state.ownerName,
          state.bookId,
        ]),
      for (final reply in replies.cast<Map>())
        for (final value in (reply['unsaved'] as List? ?? const []))
          if (value is Map)
            jsonEncode([
              reply['slot'],
              value['tabId'],
              value['ownerName'],
              value['bookId'],
            ]),
    };
    final remoteMessages = [
      for (final reply in replies.cast<Map>())
        for (final value in (reply['unsaved'] as List? ?? const []))
          if (value is Map)
            'תיקוני התוסף ‹${value['ownerName']}› בספר "${value['bookId']}" עדיין לא נשמרו לטיוטת ההתאוששות.',
    ];
    remoteMessages.addAll([
      for (final state in unsaved)
        'תיקוני התוסף ‹${state.ownerName}› בספר "${state.bookId}" עדיין לא נשמרו לטיוטת ההתאוששות.',
    ]);
    final tabs = <OpenedTab>{
      ...context.read<TabsBloc>().state.tabs,
      if (MultiViewMode.enabled)
        for (final window in AppWindowKeys.registered)
          if (window.navigator.currentContext case final other?
              when other.mounted)
            ...other.read<TabsBloc>().state.tabs,
    };
    final confirmed = await confirmCloseTabs(
      context,
      tabs,
      subtitle: _closeSubtitle(keys),
      includeClosedTabCorrections: true,
      additionalMessages: remoteMessages,
    );
    if (!confirmed) return false;
    _preparedProcessQuit = (id: requestId, peers: peers, accepted: accepted);
    retained = true;
    return true;
  } finally {
    if (!retained) await _cancelAllWindowCorrectionQuit(requestId, peers);
  }
}

Future<void> cancelPreparedProcessCorrectionQuit() async {
  final prepared = _preparedProcessQuit;
  _preparedProcessQuit = null;
  if (prepared != null) {
    await _cancelAllWindowCorrectionQuit(prepared.id, prepared.peers);
  }
}

Future<bool> finishPreparedProcessCorrectionQuit() async {
  final prepared = _preparedProcessQuit;
  if (prepared == null) return false;
  if (!MultiWindowService.correctionQuitPeersUnchanged(prepared.peers)) {
    return false;
  }
  final corrections = PluginCorrectionSessionService.instance;
  final remaining = await corrections.unsavedStates();
  final remainingIds = {
    for (final state in remaining)
      jsonEncode([
        WindowBus.instance.slot,
        state.tabId,
        state.ownerName,
        state.bookId,
      ]),
  };
  if (!remainingIds.every(prepared.accepted.contains)) return false;
  final replies = await Future.wait([
    for (final slot in prepared.peers)
      WindowBus.instance.request(
        slot,
        {
          'type': MultiWindowService.requestFinishCorrectionQuit,
          'requestId': prepared.id,
          'accepted': prepared.accepted.toList(),
        },
        timeout:
            MultiWindowService.correctionQuitRequestTimeout +
            const Duration(seconds: 2),
      ),
  ]);
  if (replies.any((reply) => reply != true) ||
      !MultiWindowService.correctionQuitPeersUnchanged(prepared.peers)) {
    return false;
  }
  _preparedProcessQuit = null;
  unawaited(
    Future.wait([
      for (final slot in prepared.peers)
        WindowBus.instance.request(
          slot,
          {
            'type': MultiWindowService.requestEndCorrectionSessions,
            'requestId': prepared.id,
          },
          timeout: MultiWindowService.correctionQuitRequestTimeout,
        ),
    ]),
  );
  await corrections.shutdown(timeout: const Duration(seconds: 5));
  return true;
}

Future<void> _cancelAllWindowCorrectionQuit(
  String requestId,
  List<int> peers,
) async {
  PluginCorrectionSessionService.instance.cancelProcessQuitPreparation(
    requestId,
  );
  await Future.wait([
    for (final slot in peers)
      WindowBus.instance.request(
        slot,
        {
          'type': MultiWindowService.requestCancelCorrectionQuit,
          'requestId': requestId,
        },
        timeout: MultiWindowService.correctionQuitRequestTimeout,
      ),
  ]);
}
