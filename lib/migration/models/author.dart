/// Represents a book author in the library.
class Author {
  /// The unique identifier of the author.
  final int id;

  /// The name of the author.
  final String name;

  /// Optional generation ID for the author.
  final int? generationId;

  const Author({
    this.id = 0,
    required this.name,
    this.generationId,
  });

  /// Creates an Author instance from a map (e.g., a database row).
  factory Author.fromMap(Map<String, dynamic> map) {
    return Author(
      id: map['id'] as int,
      name: map['name'] as String,
      generationId: map['generationId'] as int?,
    );
  }

  /// Creates an Author instance from JSON.
  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String,
      generationId: json['generationId'] as int?,
    );
  }

  /// Converts the Author to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'generationId': generationId,
    };
  }

  @override
  String toString() => 'Author(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Author &&
        other.id == id &&
        other.name == name &&
        other.generationId == generationId;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ generationId.hashCode;
}
