// core/src/commonMain/dart/io/github/kdroidfilter/seforimlibrary/core/models/link.dart

/// Types of connections between texts
enum ConnectionType {
  commentary,
  targum,
  reference,
  source,
  other,
}

/// Link between two texts (commentary, reference, etc.)
class Link {
  /// The unique identifier of the link.
  final int id;

  /// The identifier of the source book.
  final int sourceBookId;

  /// The identifier of the target book.
  final int targetBookId;

  /// The identifier of the source line.
  final int sourceLineId;

  /// The identifier of the target line.
  final int targetLineId;

  /// The type of connection between the texts.
  final ConnectionType connectionType;

  const Link({
    this.id = 0,
    required this.sourceBookId,
    required this.targetBookId,
    required this.sourceLineId,
    required this.targetLineId,
    required this.connectionType,
  });

  @override
  String toString() {
    return 'Link(id: $id, sourceBookId: $sourceBookId, targetBookId: $targetBookId, sourceLineId: $sourceLineId, targetLineId: $targetLineId, connectionType: $connectionType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Link &&
        other.id == id &&
        other.sourceBookId == sourceBookId &&
        other.targetBookId == targetBookId &&
        other.sourceLineId == sourceLineId &&
        other.targetLineId == targetLineId &&
        other.connectionType == connectionType;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        sourceBookId.hashCode ^
        targetBookId.hashCode ^
        sourceLineId.hashCode ^
        targetLineId.hashCode ^
        connectionType.hashCode;
  }
}
