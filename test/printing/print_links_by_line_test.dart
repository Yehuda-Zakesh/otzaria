import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/view/printing_screen.dart';

Link _link(int index1, {int? end, String path = 'רשי', int index2 = 1}) => Link(
  heRef: 'ref',
  index1: index1,
  index1End: end,
  path2: path,
  index2: index2,
  connectionType: 'commentary',
);

void main() {
  final links = [
    _link(1),
    _link(2, path: 'רמבן'),
    _link(2, end: 4, index2: 2),
    _link(0, end: 100, path: 'רמבן', index2: 3),
    _link(5, end: 3),
    _link(9),
    _link(3, path: 'אחר'),
  ];
  const commentators = ['רשי', 'רמבן'];

  test('each line gets only the links that cover it', () {
    final byLine = groupLinksBySourceLine(links, 2, 5);

    expect(byLine.keys.toSet(), {2, 3, 4, 5});
    expect(byLine[2], [links[1], links[2], links[3]]);
    expect(byLine[3], [links[2], links[3], links[6]]);
    expect(byLine[5], [links[3], links[4]]);
  });

  test('per-line lookup matches scanning all range links', () async {
    final byLine = groupLinksBySourceLine(links, 1, 10);
    for (var i = 0; i < 10; i++) {
      final all = await getLinksforIndexs(
        indexes: [i],
        links: links,
        commentatorsToShow: commentators,
      );
      final grouped = await getLinksforIndexs(
        indexes: [i],
        links: byLine[i + 1] ?? const [],
        commentatorsToShow: commentators,
      );
      expect(grouped, all, reason: 'line $i');
    }
  });
}
