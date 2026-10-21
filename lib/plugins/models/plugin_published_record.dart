import 'dart:convert';

class PluginPublishedRecord {
  final String pluginId;
  final String type;
  final String scope;
  final String key;
  final String payloadJson;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  const PluginPublishedRecord({
    required this.pluginId,
    required this.type,
    required this.scope,
    required this.key,
    required this.payloadJson,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.expiresAt,
  });

  factory PluginPublishedRecord.fromDbMap(Map<String, dynamic> map) {
    return PluginPublishedRecord(
      pluginId: map['plugin_id'] as String,
      type: map['type'] as String,
      scope: map['scope'] as String,
      key: map['record_key'] as String,
      payloadJson: map['payload_json'] as String,
      version: map['version'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : null,
    );
  }

  dynamic get decodedPayload => jsonDecode(payloadJson);
}
