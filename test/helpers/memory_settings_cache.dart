import 'package:otzaria/settings/engine/app_settings_store.dart';

/// CacheProvider בזיכרון לשימוש בבדיקות בלבד.
class MemorySettingsCache extends CacheProvider {
  final Map<String, dynamic> _store = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _store.containsKey(key);

  @override
  Set getKeys() => _store.keys.toSet();

  @override
  int? getInt(String key, {int? defaultValue}) =>
      (_store[key] as int?) ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      (_store[key] as String?) ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      (_store[key] as double?) ?? defaultValue;

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      (_store[key] as bool?) ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      (_store[key] as T?) ?? defaultValue;

  @override
  Future<void> setInt(String key, int? value) async =>
      value == null ? _store.remove(key) : _store[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      value == null ? _store.remove(key) : _store[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      value == null ? _store.remove(key) : _store[key] = value;

  @override
  Future<void> setBool(String key, bool? value) async =>
      value == null ? _store.remove(key) : _store[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async =>
      value == null ? _store.remove(key) : _store[key] = value;

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> removeAll() async => _store.clear();
}
