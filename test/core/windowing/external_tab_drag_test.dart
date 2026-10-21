import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/external_tab_drag.dart';

void main() {
  test('הגלובליים מאצילים למצב של החלון של ה-isolate', () {
    expect(externalTabDrag, same(ExternalTabDragState.current.drag));
    expect(externalTabDropIndex, same(ExternalTabDragState.current.dropIndex));
  });

  test('גרירה שמגיעה לחלון אחד אינה נראית בחלון אחר', () {
    final a = ExternalTabDragState();
    final b = ExternalTabDragState();
    addTearDown(() {
      a.drag.dispose();
      a.dropIndex.dispose();
      b.drag.dispose();
      b.dropIndex.dispose();
    });

    a.drag.value = const ExternalTabDrag(title: 'בראשית', local: Offset(4, 8));
    a.dropIndex.value = 2;

    expect(b.drag.value, isNull);
    expect(b.dropIndex.value, isNull);
  });
}
