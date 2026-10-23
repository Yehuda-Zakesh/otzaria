import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import 'inline_parity_harness.dart';

// התנהגות הקישורים במסלול הספאנים זהה ל-HtmlWidget: לחיצה, ריחוף, לחיצת גלגל,
// הקשת מגע והעתקה — על אותה שורה בשני המסלולים.
const _anchor =
    '<a class="link-anchor link-anchor-2 link-anchor-active" '
    'href="otzaria://anchor?ref=3_0">(א)</a>';
const _range =
    '<a class="link-anchor-range" href="otzaria://anchor?ref=3_1&range=1">שמות כט</a>';
const _inline =
    '<a href="otzaria://inline-link?path=x&index=2&ref=y" '
    'style="text-decoration: underline;">ברכות ג</a>';
const _note =
    '<a href="otzaria://note?line=7" style="text-decoration: underline; '
    'text-decoration-style: dotted; text-decoration-color: #1565c0; '
    'color: currentcolor;">הערה אישית</a>';
const _bookNote =
    'מילה<a class="book-note-marker" href="otzaria://book-note?id=4">\u2067*\u2069</a>';
const _numbered =
    '<a class="numbered-note-marker" href="otzaria://note-marker?id=1">(9)</a>';
const _line =
    'בְּרֵאשִׁית $_anchor בָּרָא $_range אֱלֹהִים $_inline אֵת $_note '
    '$_bookNote הַשָּׁמַיִם $_numbered וְאֵת הָאָרֶץ';

class _Log {
  final List<String> events = [];
}

Future<_Log> _pump(WidgetTester tester, {required bool viaHtml}) async {
  final log = _Log();
  SmartTextWidget.debugForceHtmlWidget = viaHtml;
  addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
  await tester.pumpWidget(
    parityApp(
      SmartTextWidget(
        text: _line,
        settings: const RenderSettings(fontSize: 22, lineHeight: 1.6),
        onOpenBook: (tab) => log.events.add('open:${tab.title}'),
        onNoteTap: (line) => log.events.add('note:$line'),
        onAnchorTap: (url) => log.events.add('anchor:$url'),
        onAnchorHover: (url, _) => log.events.add('enter:$url'),
        onAnchorHoverExit: (url) => log.events.add('exit:$url'),
        onTouchPreview: (url, _) => log.events.add('preview:$url'),
      ),
      width: 360,
    ),
  );
  await tester.pumpAndSettle();
  SmartTextWidget.debugForceHtmlWidget = false;
  return log;
}

/// מרכז התיבה הראשונה של [needle] בקואורדינטות גלובליות.
Offset _centerOf(WidgetTester tester, String needle) {
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byWidgetPredicate((w) => w is RichText),
  )) {
    final plain = paragraph.text.toPlainText();
    final index = plain.indexOf(needle);
    if (index < 0) continue;
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: index, extentOffset: index + needle.length),
        )
        .first;
    return paragraph.localToGlobal(box.toRect().center);
  }
  throw StateError('לא נמצא: $needle');
}

const _targets = ['(א)', 'שמות', 'ברכות', 'הערה', '*', '(9)'];

Future<List<String>> _run(
  WidgetTester tester,
  bool viaHtml,
  Future<void> Function(_Log log) action,
) async {
  final log = await _pump(tester, viaHtml: viaHtml);
  await action(log);
  return log.events;
}

void main() {
  testWidgets('לחיצת עכבר על כל סוג קישור', (tester) async {
    Future<void> clickAll(_Log log) async {
      for (final target in _targets) {
        final gesture = await tester.startGesture(
          _centerOf(tester, target),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.up();
        await gesture.removePointer();
        await tester.pump(const Duration(milliseconds: 500));
        log.events.add('--');
      }
    }

    final fast = await _run(tester, false, clickAll);
    final html = await _run(tester, true, clickAll);
    expect(fast, html);
    expect(fast, contains('anchor:otzaria://anchor?ref=3_0'));
    expect(fast, contains('note:7'));
  });

  testWidgets('הקשת מגע: תצוגה מקדימה לקישורי ריחוף', (tester) async {
    Future<void> tapAll(_Log log) async {
      for (final target in _targets) {
        await tester.tapAt(
          _centerOf(tester, target),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 500));
        log.events.add('--');
      }
    }

    final fast = await _run(tester, false, tapAll);
    final html = await _run(tester, true, tapAll);
    expect(fast, html);
    expect(
      fast,
      contains('preview:otzaria://inline-link?path=x&index=2&ref=y'),
    );
  });

  testWidgets('ריחוף: כניסה ויציאה לכל קישור', (tester) async {
    Future<void> hoverAll(_Log log) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final target in _targets) {
        await mouse.moveTo(_centerOf(tester, target));
        await tester.pump();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        log.events.add('--');
      }
      await mouse.removePointer();
    }

    final fast = await _run(tester, false, hoverAll);
    final html = await _run(tester, true, hoverAll);
    expect(fast, html);
    expect(fast, contains('enter:otzaria://anchor?ref=3_0'));
    expect(fast, contains('exit:otzaria://anchor?ref=3_0'));
  });

  testWidgets('לחיצת גלגל ויעד קישור תחת הסמן', (tester) async {
    Future<List<String>> probe(bool viaHtml) async {
      await _pump(tester, viaHtml: viaHtml);
      return [
        for (final target in _targets) ...[
          '${inlineLinkUrlAt(_centerOf(tester, target))}',
          '${recognizerAt(tester, target)?.onTertiaryTapUp != null}',
        ],
      ];
    }

    final fast = await probe(false);
    final html = await probe(true);
    expect(fast, html);
    expect(fast, contains('otzaria://inline-link?path=x&index=2&ref=y'));
  });

  testWidgets('העתקת כל השורה זהה', (tester) async {
    Future<String?> copyAll(bool viaHtml) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await _pump(tester, viaHtml: viaHtml);
      await tester.tapAt(_centerOf(tester, 'הָאָרֶץ'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      return copied;
    }

    final fast = await copyAll(false);
    final html = await copyAll(true);
    expect(fast, isNotNull);
    expect(fast, html);
  });

  testWidgets('גאומטריה, סגנון וסימונים מורמים של השורה זהים', (tester) async {
    await expectInlineParity(tester, _line, width: 360);
  });

  // המסמך שמור במטמון ומשותף; ה-recognizers שייכים לכל ווידג'ט בנפרד.
  testWidgets('אותה שורה בשתי חלוניות: recognizers נפרדים ו-callbacks חיים', (
    tester,
  ) async {
    final log = <String>[];
    Future<List<TapGestureRecognizer>> pumpPanes(
      List<(String, String)> panes,
    ) async {
      await tester.pumpWidget(
        parityApp(
          Column(
            children: [
              for (final (key, text) in panes)
                SmartTextWidget(
                  key: ValueKey(key),
                  text: text,
                  settings: const RenderSettings(fontSize: 22, lineHeight: 1.6),
                  onAnchorTap: (url) => log.add('$key:$url'),
                ),
            ],
          ),
          width: 360,
        ),
      );
      final recognizers = <TapGestureRecognizer>[];
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.byWidgetPredicate((w) => w is RichText),
      )) {
        final index = paragraph.text.toPlainText().indexOf('(א)');
        if (index < 0) continue;
        final span =
            paragraph.text.getSpanForPosition(
                  TextPosition(offset: index),
                )!
                as TextSpan;
        recognizers.add(span.recognizer! as TapGestureRecognizer);
      }
      return recognizers;
    }

    final first = await pumpPanes([('a', _line), ('b', _line)]);
    expect(first, hasLength(2));
    expect(identical(first[0], first[1]), isFalse);

    // callbacks חדשים בלי שינוי טקסט: אותם recognizers קוראים לחדשים.
    final second = await pumpPanes([('c', _line), ('b', _line)]);
    expect(identical(second[1], first[1]), isTrue);
    for (final recognizer in second) {
      recognizer.onTap!();
    }
    await tester.pump();
    expect(log, ['c:otzaria://anchor?ref=3_0', 'b:otzaria://anchor?ref=3_0']);

    // הסרת חלונית אינה פוגעת בשנייה.
    log.clear();
    final third = await pumpPanes([('b', _line)]);
    expect(identical(third.single, first[1]), isTrue);
    third.single.onTap!();
    await tester.pump();
    expect(log, ['b:otzaria://anchor?ref=3_0']);
  });
}
