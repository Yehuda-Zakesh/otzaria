part of 'commentary_search_bloc.dart';

sealed class CommentarySearchEvent {}

class CommentarySearchRequested extends CommentarySearchEvent {
  final List<Link> links;
  final String query;
  final TextDisplayProfile displayProfile;
  final bool includeSnippets;

  CommentarySearchRequested({
    required Iterable<Link> links,
    required this.query,
    required this.displayProfile,
    required this.includeSnippets,
  }) : links = List.unmodifiable(links);
}

class CommentarySearchReported extends CommentarySearchEvent {
  final int generation;
  final String key;
  final int? count;
  final List<String>? snippets;

  CommentarySearchReported({
    required this.generation,
    required this.key,
    this.count,
    this.snippets,
  });
}

class _SearchFlush extends CommentarySearchEvent {
  final int generation;
  _SearchFlush(this.generation);
}
