/// Represents a text used in table of contents entries.
class TocText {
  /// The unique identifier of the TOC text.
  final int id;

  /// The content of the TOC text.
  final String text;

  const TocText({
    this.id = 0,
    required this.text,
  });

  @override
  String toString() => 'TocText(id: $id, text: "$text")';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TocText && other.id == id && other.text == text;
  }

  @override
  int get hashCode => id.hashCode ^ text.hashCode;
}
