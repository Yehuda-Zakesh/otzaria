import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:provider/provider.dart';

/// ביצוע פעולת host דקלרטיבית של פריט תפריט הקשר (`item.action`) —
/// מסופק ע"י DeclarativePluginHost, בלי להעיר את מנוע התוסף.
typedef PluginSelectionActionDispatcher =
    Future<void> Function(
      String pluginId,
      Map<String, dynamic> actionTemplate,
      Map<String, dynamic> selectionPayload,
    );

/// איתור מבצע פעולות הסימון מעץ ה-widgets. עץ בלי PluginSystemBloc
/// (בדיקות widget) מחזיר null — פריט עם action פשוט לא יבצע דבר.
PluginSelectionActionDispatcher? pluginSelectionActionDispatcherOf(
  BuildContext context,
) {
  try {
    return context
        .read<PluginSystemBloc>()
        .declarativeHost
        ?.dispatchSelectionAction;
  } on ProviderNotFoundException {
    return null;
  }
}

/// הטקסט המסומן כפי שיימסר בלחיצה, כשהוא ידוע רק אסינכרונית: הגבלת העתקה
/// שנקראת מהמסד, או בחירת PDF שעמודיה לא נטענו.
typedef PluginSelectedTextResolver = Future<String> Function();

/// האם יש פריטי תוספים כלשהם — לפני חישוב payload שאין מי שיקבל.
bool get hasPluginContextMenuItems =>
    ContextMenuRegistry.instance.getAll().isNotEmpty;

/// שדות הספר והמקום שבכל payload של לחיצה בתפריט ההקשר.
Map<String, dynamic> pluginMenuPayload({
  required Map<String, dynamic> identity,
  required String bookTitle,
  required int sectionIndex,
  required String? currentRef,
  String text = '',
}) => {
  ...identity,
  'bookTitle': bookTitle,
  'currentBook': bookTitle,
  'currentBookId': bookTitle,
  'sectionIndex': sectionIndex,
  'currentIndex': sectionIndex,
  'currentRef': currentRef,
  'text': text,
  'start': null,
  'end': null,
};

/// פריטי התוספים של [context] כקבוצה בסוף תפריט: קו מפריד ואחריו הפריטים,
/// או רשימה ריקה כשאין פריט מתאים.
List<AppContextMenuEntry> buildPluginContextMenuSection({
  required String context,
  required Map<String, dynamic> selection,
  required BuildContext menuContext,
  PluginSelectedTextResolver? resolveSelectedText,
  List<(String pluginId, PluginContextMenuItem item)>? records,
  PluginSelectionActionDispatcher? selectionActionDispatcher,
}) {
  final entries = buildPluginContextMenuEntries(
    records: records ?? ContextMenuRegistry.instance.getAll(),
    selection: selection,
    context: context,
    selectionActionDispatcher:
        selectionActionDispatcher ??
        pluginSelectionActionDispatcherOf(menuContext),
    resolveSelectedText: resolveSelectedText,
  );
  if (entries.isEmpty) return const [];
  return [const AppContextMenuEntry.divider(), ...entries];
}

List<AppContextMenuEntry> buildPluginContextMenuEntries({
  required List<(String pluginId, PluginContextMenuItem item)> records,
  required Map<String, dynamic> selection,
  String context = 'reader-selection',
  PluginRuntimeDispatcher? dispatcher,
  PluginSelectionActionDispatcher? selectionActionDispatcher,
  PluginSelectedTextResolver? resolveSelectedText,
}) {
  final runtime = dispatcher ?? PluginRuntimeDispatcher.instance;
  final selectedText = _selectedTextOf(selection);
  final byPlugin = <String, List<PluginContextMenuItem>>{};
  for (final (pluginId, item) in records) {
    if (item.contexts.contains(context) &&
        item.isVisibleForSelection(selectedText)) {
      byPlugin.putIfAbsent(pluginId, () => []).add(item);
    }
  }
  final entries = <AppContextMenuEntry>[];
  for (final MapEntry(key: pluginId, value: items) in byPlugin.entries) {
    // קו חוצץ בין תוספים שונים כברירת מחדל; התוסף מבטל אותו בפריט הראשון שלו.
    if (entries.isNotEmpty &&
        !entries.last.isDivider &&
        items.first.separatorBefore) {
      entries.add(const AppContextMenuEntry.divider());
    }
    for (final item in items) {
      final entry = _buildEntry(
        pluginId: pluginId,
        item: item,
        selection: selection,
        context: context,
        dispatcher: runtime,
        selectionActionDispatcher: selectionActionDispatcher,
        resolveSelectedText: resolveSelectedText,
      );
      if (entry.isDivider && entries.isNotEmpty && entries.last.isDivider) {
        continue;
      }
      entries.add(entry);
    }
  }
  return entries;
}

String _selectedTextOf(Map<String, dynamic> selection) =>
    (selection['renderedSelectedText'] ?? selection['text'] ?? '').toString();

AppContextMenuEntry _buildEntry({
  required String pluginId,
  required PluginContextMenuItem item,
  required Map<String, dynamic> selection,
  required String context,
  required PluginRuntimeDispatcher dispatcher,
  PluginSelectionActionDispatcher? selectionActionDispatcher,
  PluginSelectedTextResolver? resolveSelectedText,
}) {
  if (item.type == 'separator') return const AppContextMenuEntry.divider();
  void withSelection(void Function(Map<String, dynamic> selection) send) {
    final resolve = resolveSelectedText;
    if (resolve == null) return send(selection);
    // טקסט שלא נקרא אינו היתר: התוסף מקבל את הלחיצה בלי הטקסט.
    unawaited(
      resolve()
          .then((text) => text, onError: (_) => '')
          .then((text) => send({...selection, 'text': text})),
    );
  }

  if (item.type == 'color-row') {
    return AppContextMenuEntry.colorRow([
      for (final color in item.colors)
        AppContextMenuColorAction(
          id: color.id,
          color: _parseColor(color.color),
          label: color.label,
          icon: pluginIconFromName(color.icon),
          selected: color.selected,
          onTap: () => withSelection(
            (selection) => dispatcher.dispatchEventToPlugin(
              pluginId,
              item.onColorClickEvent ?? 'contextMenu.colorClicked',
              {
                'itemId': item.id,
                'colorId': color.id,
                'color': color.color,
                'selection': selection,
              },
              preferBackground: true,
              instanceId: _targetInstanceId(dispatcher, pluginId, item),
            ),
          ),
        ),
    ]);
  }
  if (item.type == 'submenu') {
    return AppContextMenuEntry(
      label: item.label,
      icon: pluginIconFromName(item.icon),
      children: [
        for (final child in item.children)
          if (child.contexts.contains(context) &&
              child.isVisibleForSelection(_selectedTextOf(selection)))
            _buildEntry(
              pluginId: pluginId,
              item: child,
              selection: selection,
              context: context,
              dispatcher: dispatcher,
              selectionActionDispatcher: selectionActionDispatcher,
              resolveSelectedText: resolveSelectedText,
            ),
      ],
    );
  }
  final action = item.action;
  if (action != null) {
    return AppContextMenuEntry(
      label: item.label,
      icon: pluginIconFromName(item.icon),
      onTap: () => withSelection(
        (selection) => selectionActionDispatcher?.call(
          pluginId,
          action,
          _clickPayload(item: item, selection: selection),
        ),
      ),
    );
  }
  return AppContextMenuEntry(
    label: item.label,
    icon: pluginIconFromName(item.icon),
    onTap: () => withSelection(
      (selection) => dispatchPluginContextMenuItemClick(
        dispatcher: dispatcher,
        pluginId: pluginId,
        item: item,
        selection: selection,
      ),
    ),
  );
}

Map<String, dynamic> _clickPayload({
  required PluginContextMenuItem item,
  required Map<String, dynamic> selection,
}) => {
  'itemId': item.id,
  'selection': selection,
  'selectedText': selection['renderedSelectedText'] ?? selection['text'] ?? '',
  'currentRef': selection['currentRef'],
  'currentBook': selection['bookTitle'] ?? selection['currentBook'],
  'currentBookId': selection['bookId'] ?? selection['currentBookId'],
  'currentIndex': selection['sectionIndex'] ?? selection['currentIndex'],
  if (selection['id'] != null) 'id': selection['id'],
  if (selection['type'] != null) 'type': selection['type'],
  if (selection['source'] != null) 'source': selection['source'],
  'param': item.param,
};

/// מופע היעד ללחיצה על [item]: קדמי גלוי מבין המופעים שרשמו אותו, אחרת
/// הקדמי האחרון שנרשם; אין קדמי חי — null והדיספצ'ר בוחר (רקע/החייאה).
String? _targetInstanceId(
  PluginRuntimeDispatcher dispatcher,
  String pluginId,
  PluginContextMenuItem item,
) => dispatcher.pickContributionTarget(
  pluginId,
  ContextMenuRegistry.instance.instanceIdsForItem(pluginId, item.id),
);

Future<void> dispatchPluginContextMenuItemClick({
  required PluginRuntimeDispatcher dispatcher,
  required String pluginId,
  required PluginContextMenuItem item,
  required Map<String, dynamic> selection,
  PluginSelectionActionDispatcher? selectionActionDispatcher,
}) async {
  final payload = _clickPayload(item: item, selection: selection);
  if (item.action case final action?) {
    await selectionActionDispatcher?.call(pluginId, action, payload);
    return;
  }
  if (item.openPlugin) {
    // אותם אירועים כמו במסלול הרגיל, בתור המסירה של דף התוסף.
    PluginPageLauncher.instance.open(
      pluginId,
      topic: item.onClickEvent ?? 'contextMenu.itemClicked',
      payload: payload,
    );
    if (item.onClickEvent == null) {
      PluginPageLauncher.instance.open(
        pluginId,
        topic: 'reader.context_menu_item_clicked',
        payload: payload,
      );
    }
    return;
  }
  final instanceId = _targetInstanceId(dispatcher, pluginId, item);
  await dispatcher.dispatchEventToPlugin(
    pluginId,
    item.onClickEvent ?? 'contextMenu.itemClicked',
    payload,
    preferBackground: true,
    instanceId: instanceId,
  );
  if (item.onClickEvent == null) {
    await dispatcher.dispatchEventToPlugin(
      pluginId,
      'reader.context_menu_item_clicked',
      payload,
      preferBackground: true,
      instanceId: instanceId,
    );
  }
}

Color _parseColor(String value) {
  final hex = value.substring(1);
  final rgb = int.parse(hex.substring(0, 6), radix: 16);
  final alpha = hex.length == 8
      ? int.parse(hex.substring(6, 8), radix: 16)
      : 0xFF;
  return Color((alpha << 24) | rgb);
}
