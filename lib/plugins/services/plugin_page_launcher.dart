import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// מנווט לדף תוסף ומוסר לו אירועים בחלון שפתח אותו, גם כשה-boot עדיין ממתין.
class PluginPageLauncher {
  static final PluginPageLauncher instance = PluginPageLauncher._();
  PluginPageLauncher._();

  final _navigators = Expando<void Function(String pluginId)>();

  void Function(String pluginId)? get navigator =>
      _navigators[AppWindowKeys.current];
  set navigator(void Function(String pluginId)? value) =>
      _navigators[AppWindowKeys.current] = value;

  void register(AppWindowKeys keys, void Function(String pluginId) navigator) =>
      _navigators[keys] = navigator;

  void unregister(
    AppWindowKeys keys,
    void Function(String pluginId) navigator,
  ) {
    if (_navigators[keys] == navigator) _navigators[keys] = null;
  }

  final Map<
    ({String pluginId, int? viewId}),
    List<({String topic, Map<String, dynamic> payload})>
  >
  _pending = {};
  final Map<PluginInstanceKey, int?> _readyPages = {};
  final Map<({String pluginId, int? viewId}), Future<void>> _deliveryChain = {};

  bool hasPendingFor(String pluginId) => _pending.entries.any(
    (entry) => entry.key.pluginId == pluginId && entry.value.isNotEmpty,
  );

  PluginInstanceKey? _readyPage(String pluginId, int? viewId) => _readyPages
      .entries
      .where(
        (entry) =>
            entry.key.pluginId == pluginId &&
            (viewId == null || entry.value == viewId),
      )
      .firstOrNull
      ?.key;

  void open(
    String pluginId, {
    String? topic,
    Map<String, dynamic> payload = const {},
    int? viewId,
    AppWindowKeys? windowKeys,
  }) {
    if (windowKeys != null && _navigators[windowKeys] == null) return;
    if (topic != null) {
      final ready = _readyPage(pluginId, viewId);
      if (ready != null) {
        _enqueueDelivery(
          pluginId,
          topic,
          payload,
          viewId: viewId,
          instanceId: ready.instanceId,
        );
      } else {
        _pending
            .putIfAbsent((pluginId: pluginId, viewId: viewId), () => [])
            .add((topic: topic, payload: payload));
      }
    }
    _navigators[windowKeys ?? AppWindowKeys.current]?.call(pluginId);
  }

  void markPageReady(
    String pluginId, {
    String instanceId = PluginInstanceIds.defaultForeground,
    int? viewId,
  }) {
    _readyPages[(pluginId: pluginId, instanceId: instanceId)] = viewId;
    final pending = [
      ...?_pending.remove((pluginId: pluginId, viewId: viewId)),
      if (viewId != null)
        ...?_pending.remove((pluginId: pluginId, viewId: null)),
    ];
    for (final event in pending) {
      _enqueueDelivery(
        pluginId,
        event.topic,
        event.payload,
        viewId: viewId,
        instanceId: instanceId,
      );
    }
  }

  void markPageClosed(
    String pluginId, {
    String instanceId = PluginInstanceIds.defaultForeground,
    int? viewId,
  }) {
    final key = (pluginId: pluginId, instanceId: instanceId);
    final ownerView = _readyPages.containsKey(key)
        ? _readyPages.remove(key)
        : viewId;
    if (_readyPages.entries.any(
      (entry) => entry.key.pluginId == pluginId && entry.value == ownerView,
    )) {
      return;
    }
    _pending.remove((pluginId: pluginId, viewId: ownerView));
    _deliveryChain.remove((pluginId: pluginId, viewId: ownerView));
  }

  /// סגירה לפני יצירת דף אינה משאירה אירועים שממתינים לחלון שכבר איננו.
  void forgetWindow(int viewId) {
    _pending.removeWhere((key, _) => key.viewId == viewId);
    _deliveryChain.removeWhere((key, _) => key.viewId == viewId);
    _readyPages.removeWhere((_, owner) => owner == viewId);
  }

  void _enqueueDelivery(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    int? viewId,
    required String instanceId,
  }) {
    final key = (pluginId: pluginId, viewId: viewId);
    final previous = _deliveryChain[key] ?? Future<void>.value();
    final next = previous.then(
      (_) => PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        pluginId,
        topic,
        payload,
        resumeForegroundIfNeeded: true,
        instanceId: instanceId,
      ),
    );
    _deliveryChain[key] = next.catchError((_) {});
  }
}
