import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';

/// שומר בחירת בעלים בהרשאות ומסדר בקשות מתחרות בלי תור להשתלטות עתידית.
class PluginNewTabPageService {
  static final instance = PluginNewTabPageService();
  static const requestChanged = 'pluginNewTabPageChanged';
  PluginNewTabPageService({PluginNewTabPageRegistry? registry})
    : _registry = registry ?? PluginNewTabPageRegistry.instance;
  final PluginNewTabPageRegistry _registry;

  static void broadcastChanged() =>
      WindowBus.instance.broadcast({'type': requestChanged});

  Future<void> syncOwner(PluginRegistryRepository repository) =>
      _serialize(() async {
        final owner = await ownerId(repository);
        if (owner != null) {
          _registry.selectOwner(owner);
        } else {
          final current = _registry.activePluginId;
          if (current != null) _registry.remove(current);
        }
      });

  Future<void> _pending = Future.value();

  @visibleForTesting
  /// שימוש רק בין בדיקות, לאחר שכל פעולות התור הסתיימו.
  void resetQueueForTesting() => _pending = Future.value();

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<bool> request(
    String pluginId,
    PluginRegistryRepository repository, {
    required void Function(String ownerId) onConflict,
  }) => _serialize(() async {
    if (!await _authorized(pluginId, repository)) return false;
    if (await repository.getPermission(pluginId, pluginNewTabPagePermission) ==
        false) {
      return false;
    }
    final owner = await ownerId(repository);
    if (owner != null && owner != pluginId) {
      await _denyConflict(pluginId, owner, repository, onConflict);
      return false;
    }
    final granted = await _grant(
      pluginId,
      repository,
      allowPreviouslyDenied: false,
      expectedOwner: owner,
    );
    if (granted) return true;
    final currentOwner = await ownerId(repository);
    if (currentOwner != null &&
        currentOwner != pluginId &&
        await _authorized(pluginId, repository) &&
        await repository.getPermission(pluginId, pluginNewTabPagePermission) !=
            false) {
      await _denyConflict(pluginId, currentOwner, repository, onConflict);
    }
    return false;
  });

  Future<void> _denyConflict(
    String pluginId,
    String owner,
    PluginRegistryRepository repository,
    void Function(String) onConflict,
  ) async {
    await repository.setPermission(pluginId, pluginNewTabPagePermission, false);
    onConflict(owner);
  }

  Future<String?> ownerId(PluginRegistryRepository repository) =>
      repository.getNewTabPageOwner();

  Future<bool> grant(
    String pluginId,
    PluginRegistryRepository repository, {
    required String? expectedOwner,
  }) => _serialize(() async {
    if (await repository.getPermission(pluginId, pluginNewTabPagePermission) ==
        null) {
      return false;
    }
    return _grant(pluginId, repository, expectedOwner: expectedOwner);
  });

  Future<bool> _authorized(
    String pluginId,
    PluginRegistryRepository repository,
  ) async {
    final plugin = await repository.getPlugin(pluginId);
    return plugin?.enabled == true &&
        plugin!.manifest.permissions.contains('navigation.write') &&
        await repository.getPermission(pluginId, 'navigation.write') == true;
  }

  Future<void> release(String pluginId, PluginRegistryRepository repository) =>
      _serialize(() async {
        await repository.clearNewTabPageRegistration(pluginId);
        _registry.remove(pluginId);
        broadcastChanged();
      });

  Future<bool> _grant(
    String pluginId,
    PluginRegistryRepository repository, {
    bool allowPreviouslyDenied = true,
    required String? expectedOwner,
  }) async {
    if (!await _authorized(pluginId, repository)) return false;
    return repository.grantNewTabPage(
      pluginId,
      allowPreviouslyDenied: allowPreviouslyDenied,
      expectedOwner: expectedOwner,
      onGranted: () {
        if (_registry.activePluginId == pluginId) return;
        _registry.selectOwner(pluginId);
        broadcastChanged();
      },
    );
  }
}
