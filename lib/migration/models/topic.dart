/// Represents a topic (keyword) associated with books in the library.
class Topic {
  /// The unique identifier of the topic.
  final int id;

  /// The name of the topic.
  final String name;

  const Topic({
    this.id = 0,
    required this.name,
  });

  /// Creates a Topic instance from JSON.
  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String,
    );
  }

  /// Converts the Topic to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  String toString() => 'Topic(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Topic && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
