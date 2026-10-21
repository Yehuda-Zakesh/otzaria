part of 'commentary_search_bloc.dart';

class CommentarySearchState {
  final Map<String, int> counts;
  final Map<String, int> countsByPath;
  final List<CommentarySearchSnippet> snippets;
  final int total;

  const CommentarySearchState.empty()
    : counts = const {},
      countsByPath = const {},
      snippets = const [],
      total = 0;

  CommentarySearchState({
    required List<Link> links,
    required String Function(Link) keyOf,
    required Map<String, int> counts,
    required Map<String, List<String>> snippetsByKey,
  }) : counts = Map.unmodifiable(counts),
       countsByPath = Map.unmodifiable(
         commentarySearchCountsByPath(
           counts,
           {for (final link in links) keyOf(link): link.path2},
         ),
       ),
       snippets = List.unmodifiable(
         orderCommentarySearchSnippets<Link>(
           items: links,
           keyOf: keyOf,
           pathOf: (link) => link.path2,
           countsByKey: counts,
           snippetsOf: (key, count) =>
               count > 0 ? snippetsByKey[key] ?? const [] : const [],
         ),
       ),
       total = totalCommentarySearchResults(counts);
}
