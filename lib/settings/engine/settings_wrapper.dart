import 'package:otzaria/settings/engine/app_settings_store.dart';

/// A wrapper around the static Settings class to make it more testable.
/// This allows us to mock the Settings class in tests.
class SettingsWrapper {
  /// Gets a value from settings with a default value if not found.
  T getValue<T>(String key, {required T defaultValue}) {
    return Settings.getValue<T>(key, defaultValue: defaultValue) ??
        defaultValue;
  }

  /// Sets a value in settings.
  Future<void> setValue<T>(String key, T value) {
    return Settings.setValue<T>(key, value);
  }

  /// Removes a value from settings.
  Future<void> remove(String key) {
    return Settings.setValue<String?>(key, null);
  }
}
