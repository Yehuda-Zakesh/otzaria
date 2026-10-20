import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// A declarative action for test items: the click is recorded by
/// [PluginMenuClickRecorder] instead of running.
const kRecordedAction = {
  'type': 'storage.set',
  'args': {
    'key': 'last',
    'value': {r'$selection': 'selectedText'},
  },
};

/// Registers plugin context-menu items with a declarative action and records
/// the payload of each click, as the host would receive it.
class PluginMenuClickRecorder {
  PluginMenuClickRecorder(this.pluginId);

  final String pluginId;
  final clicks = <Map<String, dynamic>>[];
  late final PluginSystemBloc bloc = _RecordingPluginSystemBloc(clicks);

  /// Registers an item titled [title] in [contexts], and removes it in
  /// tearDown.
  void register(String id, String title, List<String> contexts) {
    ContextMenuRegistry.instance.registerPayload(pluginId, {
      'id': id,
      'title': title,
      'contexts': contexts,
      'action': kRecordedAction,
    });
    addTearDown(() => ContextMenuRegistry.instance.removeAll(pluginId));
  }

  /// Provides [bloc] to [child], so menus built below it find the host.
  Widget wrap(Widget child) =>
      BlocProvider<PluginSystemBloc>.value(value: bloc, child: child);

  /// Taps [entry] and waits for the payload, which may resolve on click.
  Future<Map<String, dynamic>> click(
    WidgetTester tester,
    AppContextMenuEntry entry,
  ) async {
    await tester.runAsync(() async {
      entry.onTap!();
      for (var i = 0; i < 50 && clicks.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(clicks, hasLength(1), reason: 'the item did not dispatch');
    return clicks.removeLast();
  }
}

class _RecordingPluginSystemBloc
    extends Bloc<PluginSystemEvent, PluginSystemState>
    implements PluginSystemBloc {
  _RecordingPluginSystemBloc(List<Map<String, dynamic>> clicks)
    : declarativeHost = _RecordingHost(clicks),
      super(PluginSystemInitial());

  @override
  final DeclarativePluginHost declarativeHost;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHost implements DeclarativePluginHost {
  _RecordingHost(this.clicks);

  final List<Map<String, dynamic>> clicks;

  @override
  Future<void> dispatchSelectionAction(
    String pluginId,
    Map<String, dynamic> actionTemplate,
    Map<String, dynamic> selectionPayload,
  ) async => clicks.add(selectionPayload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
