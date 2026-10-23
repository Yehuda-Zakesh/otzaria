import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';

const _style = TextStyle(fontSize: 20);
const _url = 'otzaria://inline-link?path=x&index=2';
const _anchor = 'otzaria://anchor?ref=3_0';
const _html = '<a href="$_url"><b>ספר</b></a> <a href="$_anchor">עוגן</a>';

List<TextSpan> _leaves(WidgetTester tester) {
  final result = <TextSpan>[];
  void visit(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text != null) result.add(span);
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child);
    }
  }

  visit(tester.widget<RichText>(find.byType(RichText)).text);
  return result;
}

TextSpan _leaf(WidgetTester tester, String text) =>
    _leaves(tester).firstWhere((span) => span.text == text);

Future<void> _pump(
  WidgetTester tester, {
  String html = _html,
  int copies = 1,
  ContinuousReadingUrlTap? onTap,
  ContinuousReadingAnchorHover? onHover,
  ContinuousReadingAnchorExit? onExit,
  void Function(String)? onMiddle,
  TextStyle? linkStyle,
  TextStyle style = _style,
}) => tester.pumpWidget(
  MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: ContinuousReadingParagraph(
        lines: [
          for (var i = 0; i < copies; i++)
            ContinuousReadingParagraphLine(
              lineIndex: i,
              htmlText: html,
              style: style,
            ),
        ],
        baseStyle: style,
        onTapUrl: onTap,
        onAnchorHover: onHover,
        onAnchorExit: onExit,
        onMiddleClickUrl: onMiddle,
        linkStyle: linkStyle,
      ),
    ),
  ),
);

void main() {
  testWidgets('שומר את הספאנים וקורא callbacks עדכניים בכל סוגי האירועים', (
    tester,
  ) async {
    final events = <String>[];
    Future<void> pump(String tag) => _pump(
      tester,
      onTap: (url) async {
        events.add('$tag:tap:$url');
        return true;
      },
      onHover: (url, _) => events.add('$tag:hover:$url'),
      onExit: (url) => events.add('$tag:exit:$url'),
      onMiddle: (url) => events.add('$tag:middle:$url'),
    );
    await pump('old');
    final book = _leaf(tester, 'ספר');
    final anchor = _leaf(tester, 'עוגן');
    final recognizer = book.recognizer! as TapGestureRecognizer;
    await pump('new');
    expect(_leaf(tester, 'ספר'), same(book));
    expect(_leaf(tester, 'עוגן'), same(anchor));
    recognizer.onTap!();
    recognizer.onTertiaryTapUp!(
      TapUpDetails(kind: PointerDeviceKind.mouse),
    );
    anchor.onEnter!(const PointerEnterEvent());
    anchor.onExit!(const PointerExitEvent());
    await tester.pump();
    expect(events, [
      'new:tap:$_url',
      'new:middle:$_url',
      'new:hover:$_anchor',
      'new:exit:$_anchor',
    ]);
  });

  testWidgets('שינוי נוכחות callbacks מוסיף ומסיר את התנהגות הקישור', (
    tester,
  ) async {
    await _pump(tester);
    expect(_leaf(tester, 'ספר').recognizer, isNull);
    Future<bool> tap(String _) async => true;
    await _pump(tester, onTap: tap);
    final first = _leaf(tester, 'ספר').recognizer;
    expect(first, isNotNull);
    expect(_leaf(tester, 'עוגן').onEnter, isNull);
    await _pump(tester, onTap: tap, onHover: (_, _) {}, onExit: (_) {});
    expect(_leaf(tester, 'עוגן').onEnter, isNotNull);
    expect(_leaf(tester, 'עוגן').onExit, isNotNull);
    await _pump(tester, onTap: tap, onMiddle: (_) {});
    final middle = _leaf(tester, 'ספר').recognizer! as TapGestureRecognizer;
    expect(middle.onTertiaryTapUp, isNotNull);
    expect(_leaf(tester, 'עוגן').onEnter, isNull);
    expect(_leaf(tester, 'עוגן').onExit, isNull);
    await _pump(tester, onTap: tap);
    final withoutMiddle =
        _leaf(tester, 'ספר').recognizer! as TapGestureRecognizer;
    expect(withoutMiddle.onTertiaryTapUp, isNull);
    await _pump(tester);
    expect(_leaf(tester, 'ספר').recognizer, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('שינוי עיצוב קישור וסגנון שורה מעדכן ספאנים שמורים', (
    tester,
  ) async {
    Future<bool> tap(String _) async => true;
    await _pump(
      tester,
      onTap: tap,
      linkStyle: const TextStyle(color: Colors.red),
    );
    final red = _leaf(tester, 'ספר');
    expect(red.style!.color, Colors.red);
    await _pump(
      tester,
      onTap: tap,
      linkStyle: const TextStyle(color: Colors.blue),
    );
    final blue = _leaf(tester, 'ספר');
    expect(blue.style!.color, Colors.blue);
    expect(blue, isNot(same(red)));
    await _pump(
      tester,
      onTap: tap,
      linkStyle: const TextStyle(color: Colors.blue),
      style: const TextStyle(fontSize: 28),
    );
    expect(_leaf(tester, 'ספר').style!.fontSize, 28);
  });

  testWidgets('שורות כפולות חולקות מטמון עד האחרונה ויוצאות ממנו כשהוסרו', (
    tester,
  ) async {
    final disposed = <Object>[];
    void listener(ObjectEvent event) {
      if (event is ObjectDisposed) disposed.add(event.object);
    }

    FlutterMemoryAllocations.instance.addListener(listener);
    addTearDown(
      () => FlutterMemoryAllocations.instance.removeListener(listener),
    );
    Future<bool> tap(String _) async => true;
    await _pump(tester, copies: 2, onTap: tap);
    final books = _leaves(tester).where((span) => span.text == 'ספר').toList();
    expect(books, hasLength(2));
    expect(books[0], same(books[1]));
    final recognizer = books.first.recognizer! as TapGestureRecognizer;
    await _pump(tester, onTap: tap);
    expect(_leaf(tester, 'ספר').recognizer, same(recognizer));
    recognizer.onTap!();
    expect(disposed.where((object) => identical(object, recognizer)), isEmpty);
    await _pump(tester, copies: 0, onTap: tap);
    expect(
      disposed.where((object) => identical(object, recognizer)),
      hasLength(1),
    );
    await _pump(tester, onTap: tap);
    final fresh = _leaf(tester, 'ספר').recognizer! as TapGestureRecognizer;
    expect(fresh, isNot(same(recognizer)));
    await tester.pumpWidget(const SizedBox());
    expect(disposed.where((object) => identical(object, fresh)), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('מטמון קישורים משמר רווחים, br, גודל rem ותוכן להעתקה', (
    tester,
  ) async {
    const html =
        'א   ב&nbsp;<br><a href="$_url">'
        '<span style="font-size:2rem">שָׁלוֹם</span></a><br><br>';
    Future<bool> tap(String _) async => true;
    await _pump(tester, html: html, onTap: tap);
    final before = tester.widget<RichText>(find.byType(RichText)).text;
    await _pump(tester, html: html, onTap: tap);
    final after = tester.widget<RichText>(find.byType(RichText)).text;
    expect(before.toPlainText(), 'א   ב\u00a0\nשָׁלוֹם\n\n');
    expect(after.toPlainText(), before.toPlainText());
    expect(_leaf(tester, 'שָׁלוֹם').style!.fontSize, 40);
  });
}
