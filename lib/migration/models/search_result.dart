/// Represents a search result
class SearchResult {
  /// The identifier of the book containing the result
  final int bookId;

  /// The title of the book containing the result
  final String bookTitle;

  /// The identifier of the line containing the result
  final int lineId;

  /// The index of the line containing the result
  final int lineIndex;

  /// The text excerpt with highlighting
  final String snippet;

  /// The relevance score of the result
  final double rank;

  const SearchResult({
    required this.bookId,
    required this.bookTitle,
    required this.lineId,
    required this.lineIndex,
    required this.snippet,
    required this.rank,
  });

  @override
  String toString() {
    return 'SearchResult(bookId: $bookId, bookTitle: $bookTitle, lineId: $lineId, lineIndex: $lineIndex, snippet: "$snippet", rank: $rank)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SearchResult &&
        other.bookId == bookId &&
        other.bookTitle == bookTitle &&
        other.lineId == lineId &&
        other.lineIndex == lineIndex &&
        other.snippet == snippet &&
        other.rank == rank;
  }

  @override
  int get hashCode {
    return bookId.hashCode ^
        bookTitle.hashCode ^
        lineId.hashCode ^
        lineIndex.hashCode ^
        snippet.hashCode ^
        rank.hashCode;
  }
}
