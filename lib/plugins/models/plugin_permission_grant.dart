class PluginPermissionGrant {
  final String pluginId;
  final String permission;
  final bool granted;
  final DateTime grantedAt;

  const PluginPermissionGrant({
    required this.pluginId,
    required this.permission,
    required this.granted,
    required this.grantedAt,
  });

  factory PluginPermissionGrant.fromDbMap(Map<String, dynamic> map) {
    return PluginPermissionGrant(
      pluginId: map['plugin_id'] as String,
      permission: map['permission'] as String,
      granted: (map['granted'] as int) != 0,
      grantedAt: DateTime.parse(map['granted_at'] as String),
    );
  }
}
