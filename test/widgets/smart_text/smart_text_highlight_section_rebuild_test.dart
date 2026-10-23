import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

const _text = 'ראש טקסט סוף';
const _bookTitle = 'גיטין';
const _pluginId = 'plugin.section.rebuild.test';
const _otherPluginId = 'plugin.section.rebuild.other';

Map<String, dynamic> _payload({required String id, required int section}) => {
  'highlightId': id,
  'bookId': _bookTitle,
  'sectionIndex': section,
  'range': {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'sourceTextHash':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'layer': 'source',
    'start': {'grapheme': 4, 'codePoint': 4, 'utf16': 4},
    'end': {'grapheme': 8, 'codePoint': 8, 'utf16': 8},
    'exactText': 'טקסט',
    'beforeText': {
      'raw': 'ראש ',
      'normalized': 'ראש ',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'afterText': {
      'raw': ' סוף',
      'normalized': ' סוף',
      'maxGraphemes': 30,
      'actualGraphemes': 4,
      'truncatedAtBoundary': true,
    },
    'occurrenceIndexInSection': 0,
    'occurrenceCountInSection': 1,
  },
  'style': {'backgroundColor': '#FFE066'},
};

Widget _lines(int count, {bool forceHtmlWidget = false}) {
  SmartTextWidget.debugForceHtmlWidget = forceHtmlWidget;
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          for (var i = 0; i < count; i++)
            SmartTextWidget(
              text: _text,
              settings: const RenderSettings(fontSize: 20),
              highlightBookId: _bookTitle,
              highlightSectionIndex: i,
            ),
        ],
      ),
    ),
  );
}

/// הקטעים שה-ListenableBuilder של השורה שלהם נבנה מחדש.
final _rebuiltSections = <int>{};

void _onRebuild(Element element, bool builtOnce) {
  if (element.widget is! ListenableBuilder) return;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is! SmartTextWidget) return true;
    _rebuiltSections.add(widget.highlightSectionIndex!);
    return false;
  });
}

Set<int> _takeRebuilt() {
  final result = Set.of(_rebuiltSections);
  _rebuiltSections.clear();
  return result;
}

Set<int> _drawnSections(WidgetTester tester) => tester
    .widgetList<PluginHighlightFrameOverlay>(
      find.byType(PluginHighlightFrameOverlay),
    )
    .expand((overlay) => overlay.ranges)
    .map((range) => range.highlight.sectionIndex)
    .toSet();

bool _hasRevealDecoration(
  TextSpan span, [
  TextStyle inherited = const TextStyle(),
]) {
  final style = inherited.merge(span.style);
  final decoration = style.decoration;
  if (span.text?.contains('טקסט') == true &&
      decoration?.contains(TextDecoration.underline) == true &&
      decoration?.contains(TextDecoration.overline) == true) {
    return true;
  }
  return span.children?.whereType<TextSpan>().any(
        (child) => _hasRevealDecoration(child, style),
      ) ??
      false;
}

Set<int> _revealedSections(WidgetTester tester) => {
  for (var section = 0; section < 5; section++)
    if (tester
        .renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is SmartTextWidget &&
                  widget.highlightSectionIndex == section,
            ),
            matching: find.byType(RichText),
          ),
        )
        .any(
          (paragraph) => _hasRevealDecoration(paragraph.text as TextSpan),
        ))
      section,
};

void main() {
  setUp(() {
    SmartTextWidget.debugForceHtmlWidget = false;
    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    PluginHighlightRegistry.instance.removePlugin(_otherPluginId);
    PluginHighlightRevealService.instance.clear();
    _rebuiltSections.clear();
    debugOnRebuildDirtyWidget = _onRebuild;
  });

  tearDown(() {
    SmartTextWidget.debugForceHtmlWidget = false;
    debugOnRebuildDirtyWidget = null;
    PluginHighlightRevealService.instance.clear();
    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    PluginHighlightRegistry.instance.removePlugin(_otherPluginId);
  });

  testWidgets('הדגשה חדשה בונה מחדש רק את השורה של הקטע שלה', (tester) async {
    await tester.pumpWidget(_lines(5));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h2', section: 2),
    );
    await tester.pumpAndSettle();

    expect(_takeRebuilt(), {2});
    expect(_drawnSections(tester), {2});

    PluginHighlightRegistry.instance.removePlugin(_pluginId);
    await tester.pumpAndSettle();

    expect(_takeRebuilt(), {2});
    expect(_drawnSections(tester), isEmpty);
  });

  testWidgets('חשיפת הדגשה בונה מחדש רק את הקטע שלה, גם בכניסה וגם ביציאה', (
    tester,
  ) async {
    final highlight = PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h3', section: 3),
    );
    await tester.pumpWidget(_lines(5));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRevealService.instance.reveal(highlight);
    await tester.pump();
    expect(_takeRebuilt(), {3});

    PluginHighlightRevealService.instance.clear();
    await tester.pump();
    expect(_takeRebuilt(), {3});
  });

  testWidgets('סיום חשיפה של הדגשה שהועברה בונה מחדש את הקטע החדש', (
    tester,
  ) async {
    final highlight = PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h1', section: 1),
    );
    await tester.pumpWidget(_lines(5));
    await tester.pumpAndSettle();
    PluginHighlightRevealService.instance.reveal(highlight);
    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h1', section: 3),
    );
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRevealService.instance.clear();
    await tester.pump();
    expect(_takeRebuilt(), contains(3));
  });

  testWidgets('שורה שהוסרה מהעץ אינה נשארת רשומה לקטע', (tester) async {
    await tester.pumpWidget(_lines(3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_lines(1));
    await tester.pumpAndSettle();
    _takeRebuilt();

    PluginHighlightRegistry.instance.setHighlight(
      ownerPluginId: _pluginId,
      payload: _payload(id: 'h2', section: 2),
    );
    await tester.pumpAndSettle();

    expect(_takeRebuilt(), isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final forceHtmlWidget in [false, true]) {
    for (final otherInstance in [false, true]) {
      for (final presentBeforeReveal in [false, true]) {
        testWidgets(
          'חשיפה מסתיימת בכל הקטעים עם מזהה משותף: '
          'מופע אחר=$otherInstance, נרשם מראש=$presentBeforeReveal, '
          'HtmlWidget=$forceHtmlWidget',
          (tester) async {
            final registry = PluginHighlightRegistry.instance;
            final reveal = PluginHighlightRevealService.instance;
            final highlight = registry.setHighlight(
              ownerPluginId: _pluginId,
              payload: _payload(id: 'shared', section: 1),
            );
            void setOther() => registry.setHighlight(
              ownerPluginId: otherInstance ? _pluginId : _otherPluginId,
              ownerInstanceId: 'other-instance',
              payload: _payload(id: 'shared', section: 3),
            );
            if (presentBeforeReveal) setOther();
            await tester.pumpWidget(
              _lines(5, forceHtmlWidget: forceHtmlWidget),
            );
            await tester.pumpAndSettle();
            _takeRebuilt();

            reveal.reveal(highlight);
            await tester.pump();
            expect(_takeRebuilt(), presentBeforeReveal ? {1, 3} : {1});
            if (!presentBeforeReveal) {
              setOther();
              await tester.pumpAndSettle();
              expect(_takeRebuilt(), {3});
            }
            expect(_revealedSections(tester), {1, 3});

            reveal.clear();
            await tester.pump();
            expect(_revealedSections(tester), isEmpty);
            expect(_takeRebuilt(), {1, 3});
          },
        );
      }
    }
  }

  for (final forceHtmlWidget in [false, true]) {
    testWidgets(
      'העברה, הסרה ורישום מחדש בזמן חשיפה מעדכנים רק קטעים מושפעים, '
      'HtmlWidget=$forceHtmlWidget',
      (tester) async {
        final registry = PluginHighlightRegistry.instance;
        final reveal = PluginHighlightRevealService.instance;
        final highlight = registry.setHighlight(
          ownerPluginId: _pluginId,
          payload: _payload(id: 'shared', section: 1),
        );
        await tester.pumpWidget(_lines(5, forceHtmlWidget: forceHtmlWidget));
        await tester.pumpAndSettle();
        reveal.reveal(highlight);
        registry.setHighlight(
          ownerPluginId: _otherPluginId,
          payload: _payload(id: 'shared', section: 3),
        );
        await tester.pumpAndSettle();
        _takeRebuilt();
        registry.setHighlight(
          ownerPluginId: _otherPluginId,
          payload: _payload(id: 'shared', section: 4),
        );
        await tester.pumpAndSettle();
        expect(_takeRebuilt(), {3, 4});
        expect(_revealedSections(tester), {1, 4});

        registry.clearHighlight(
          ownerPluginId: _pluginId,
          highlightId: 'shared',
        );
        await tester.pumpAndSettle();
        expect(_takeRebuilt(), {1});
        expect(_revealedSections(tester), {4});
        registry.setHighlight(
          ownerPluginId: _pluginId,
          payload: _payload(id: 'shared', section: 2),
        );
        await tester.pumpAndSettle();
        expect(_takeRebuilt(), {2});
        expect(_revealedSections(tester), {2, 4});

        reveal.clear();
        await tester.pump();
        expect(_revealedSections(tester), isEmpty);
        expect(_takeRebuilt(), {2, 4});
      },
    );
  }

  for (final forceHtmlWidget in [false, true]) {
    testWidgets(
      'החלפת מזהה החשיפה מעדכנת את כל עותקי המזהה הקודם והחדש, '
      'HtmlWidget=$forceHtmlWidget',
      (tester) async {
        final registry = PluginHighlightRegistry.instance;
        final reveal = PluginHighlightRevealService.instance;
        final first = registry.setHighlight(
          ownerPluginId: _pluginId,
          payload: _payload(id: 'shared', section: 1),
        );
        registry.setHighlight(
          ownerPluginId: _otherPluginId,
          payload: _payload(id: 'shared', section: 3),
        );
        final second = registry.setHighlight(
          ownerPluginId: _pluginId,
          payload: _payload(id: 'second', section: 2),
        );
        await tester.pumpWidget(_lines(5, forceHtmlWidget: forceHtmlWidget));
        await tester.pumpAndSettle();
        reveal.reveal(first);
        await tester.pump();
        expect(_revealedSections(tester), {1, 3});
        _takeRebuilt();

        reveal.reveal(second);
        await tester.pump();
        expect(_revealedSections(tester), {2});
        expect(_takeRebuilt(), {1, 2, 3});
        reveal.clear();
        await tester.pump();
        expect(_revealedSections(tester), isEmpty);
        expect(_takeRebuilt(), {2});
      },
    );
  }
}
