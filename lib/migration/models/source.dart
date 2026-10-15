/// Represents a source of books in the database.
class Source {
  final int id;
  final String name;

  const Source({
    required this.id,
    required this.name,
  });

  factory Source.fromJson(Map<String, dynamic> json) {
    return Source(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }
}
