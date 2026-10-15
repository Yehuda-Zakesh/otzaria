import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';

/// בעלות התוסף על '+' שורדת סגירת WebView; מתחרה אינו ממתין להשתלטות עתידית.
class PluginNewTabPageRegistry extends ChangeNotifier {
  static final PluginNewTabPageRegistry instance = PluginNewTabPageRegistry._();
  PluginNewTabPageRegistry._() : _repository = PluginRegistryRepository();
  @visibleForTesting
  PluginNewTabPageRegistry.forTesting(PluginRegistryRepository repository)
    : _repository = repository;
  final PluginRegistryRepository _repository;
  @visibleForTesting
  PluginRegistryRepository? repositoryForTesting;

  String? _activePluginId;

  /// Returns false when another plugin already owns the new-tab button.
  /// Re-registering the current owner is an idempotent success.
  bool register(String pluginId) {
    if (_activePluginId == pluginId) return true;
    if (_activePluginId != null) return false;
    selectOwner(pluginId);
    return true;
  }

  /// שינוי בעלים שכבר אושר ונשמר בהרשאות התוספים.
  void selectOwner(String pluginId) {
    if (_activePluginId == pluginId) return;
    _activePluginId = pluginId;
    notifyListeners();
  }

  void remove(String pluginId) {
    if (_activePluginId != pluginId) return;
    _activePluginId = null;
    notifyListeners();
  }

  bool get hasActiveRegistration => _activePluginId != null;

  String? get activePluginId => _activePluginId;

  /// Opens the registered plugin page. With no registration the button is hidden.
  Future<void> open() async {
    if (activePluginId == null) return;
    final pluginId = await (repositoryForTesting ?? _repository)
        .getNewTabPageOwner();
    if (pluginId == null) {
      final current = activePluginId;
      if (current != null) remove(current);
      return;
    }
    selectOwner(pluginId);
    PluginPageLauncher.instance.open(
      pluginId,
      topic: 'plugin.page_opened',
      payload: const {'source': 'newTabButton'},
    );
  }
}
