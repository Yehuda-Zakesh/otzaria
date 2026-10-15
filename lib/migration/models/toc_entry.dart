/// Table of contents entry.
class TocEntry {
  /// The unique identifier of the TOC entry.
  final int id;

  /// The identifier of the book this TOC entry belongs to.
  final int bookId;

  /// The identifier of the parent TOC entry, or null if this is a root entry.
  final int? parentId;

  /// The identifier of the associated text in the tocText table.
  final int? textId;

  /// The text of the TOC entry (for compatibility with existing code).
  final String text;

  /// The level of the TOC entry in the hierarchy.
  final int level;

  /// The identifier of the associated line, or null if not linked to a specific line.
  final int? lineId;

  /// The index of the associated line in the book (0-based).
  final int? lineIndex;

  /// Indicates if this TOC entry is the last child of its parent.
  final bool isLastChild;

  /// Indicates if this TOC entry has children.
  final bool hasChildren;

  const TocEntry({
    this.id = 0,
    required this.bookId,
    this.parentId,
    this.textId,
    this.text = "",
    required this.level,
    this.lineId,
    this.lineIndex,
    this.isLastChild = false,
    this.hasChildren = false,
  });

  /// Creates a TocEntry instance from a map (e.g., a database row).
  factory TocEntry.fromMap(Map<String, dynamic> map) {
    return TocEntry(
      id: map['id'] as int,
      bookId: map['bookId'] as int,
      parentId: map['parentId'] as int?,
      textId: map['textId'] as int?,
      text: map['text'] as String? ?? '',
      level: map['level'] as int,
      lineId: map['lineId'] as int?,
      lineIndex: map['lineIndex'] as int?,
      isLastChild: (map['isLastChild'] ?? 0) == 1,
      hasChildren: (map['hasChildren'] ?? 0) == 1,
    );
  }

  @override
  String toString() =>
      'TocEntry(id: $id, bookId: $bookId, level: $level, text: "$text")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TocEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
