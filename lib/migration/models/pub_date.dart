/// Represents a publication date.
class PubDate {
  /// The unique identifier of the publication date.
  final int id;

  /// The publication date as a string.
  final String date;

  const PubDate({
    this.id = 0,
    required this.date,
  });

  /// Creates a PubDate instance from JSON.
  factory PubDate.fromJson(Map<String, dynamic> json) {
    return PubDate(
      id: json['id'] as int? ?? 0,
      date: json['date'] as String,
    );
  }

  /// Converts the PubDate to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
    };
  }

  @override
  String toString() => 'PubDate(id: $id, date: $date)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PubDate && other.id == id && other.date == date;
  }

  @override
  int get hashCode => id.hashCode ^ date.hashCode;
}
