/// Represents an individual line of a book
class Line {
  /// The unique identifier of the line
  final int id;

  /// The identifier of the book this line belongs to
  final int bookId;

  /// The index of the line within the book
  final int lineIndex;

  /// The original HTML content of the line
  final String content;

  /// Hebrew reference (e.g., "בראשית א:א") for the line
  final String? heRef;

  const Line({
    this.id = 0,
    required this.bookId,
    required this.lineIndex,
    required this.content,
    this.heRef,
  });

  @override
  String toString() {
    return 'Line(id: $id, bookId: $bookId, lineIndex: $lineIndex, heRef: $heRef, content: "$content")';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Line &&
        other.id == id &&
        other.bookId == bookId &&
        other.lineIndex == lineIndex &&
        other.content == content &&
        other.heRef == heRef;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      bookId,
      lineIndex,
      content,
      heRef,
    );
  }
}
