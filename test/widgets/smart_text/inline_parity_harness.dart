// כלי השוואה בין מסלול הספאנים של SmartTextWidget לבין HtmlWidget על אותו קלט.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

/// מה שהעין והעכבר רואים בשורה: גאומטריה, טקסט, סגנון לכל תו והתנהגות קישור.
class RenderedLine {
  RenderedLine({
    required this.usedHtmlWidget,
    required this.size,
    required this.text,
    required this.paragraphs,
    required this.lines,
    required this.carets,
    required this.charStyles,
    required this.markers,
  });

  final bool usedHtmlWidget;
  final Size size;
  final String text;
  final List<Rect> paragraphs;

  /// מלבן כל שורה חזותית (איחוד תיבות הבחירה שבה).
  final List<Rect> lines;

  /// מיקום הסמן לפני כל יחידת UTF-16 — מיקום כל גליף ושבירת השורות.
  final List<Offset> carets;

  /// חתימת סגנון והתנהגות לכל יחידת UTF-16 בטקסט.
  final List<String> charStyles;
  final List<String> markers;
}

String _colorSig(Color? color) =>
    color == null ? '-' : color.toARGB32().toRadixString(16);

/// הסגנון האפקטיבי כפי שהמנוע מצייר אותו: קו בלי צבע נצבע בצבע הטקסט,
/// ורקע הוא Paint או backgroundColor.
String styleSignature(TextStyle style, TextSpan span) {
  final decoration = style.decoration ?? TextDecoration.none;
  final hasLine = decoration != TextDecoration.none;
  final variations = style.fontVariations;
  return [
    'size=${style.fontSize?.toStringAsFixed(4)}',
    'family=${style.fontFamily}',
    'fallback=${(style.fontFamilyFallback ?? const []).join(',')}',
    'weight=${style.fontWeight?.value ?? 400}',
    'italic=${style.fontStyle == FontStyle.italic}',
    'var=${variations == null || variations.isEmpty ? '-' : variations.map((v) => '${v.axis}${v.value}').join(',')}',
    'height=${style.height}',
    'color=${_colorSig(style.color)}',
    'deco=$decoration',
    if (hasLine) ...[
      'decoStyle=${style.decorationStyle ?? TextDecorationStyle.solid}',
      'decoColor=${_colorSig(style.decorationColor ?? style.color)}',
      'decoThick=${style.decorationThickness ?? 1.0}',
    ],
    'bg=${_colorSig(style.background?.color ?? style.backgroundColor)}',
    'link=${span.recognizer != null}',
    'hover=${span.onEnter != null}/${span.onExit != null}',
    'cursor=${span.recognizer == null && span.onEnter == null ? '-' : span.mouseCursor}',
  ].join(' ');
}

void _collect(
  InlineSpan span,
  TextStyle inherited,
  List<String> out,
  List<(TextSpan, int)> leaves,
) {
  if (span is! TextSpan) {
    out.add('widget');
    return;
  }
  final style = span.style == null ? inherited : inherited.merge(span.style);
  final text = span.text;
  if (text != null) {
    final sig = styleSignature(style, span);
    for (var i = 0; i < text.length; i++) {
      out.add(sig);
    }
    leaves.add((span, text.length));
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    _collect(child, style, out, leaves);
  }
}

/// צבעי ערכת נושא בולטים, כדי שצבע שגוי לא יעבור בשתיקה.
final ThemeData parityTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6A1B9A)),
);

/// ערכת נושא אפורה: בה צבע הקישורים של הקורא שונה מ-primary.
final ThemeData parityGreyTheme = ThemeData(
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF808080),
    onSurface: Color(0xFFE0E0E0),
  ),
);

Widget parityApp(Widget child, {double width = 320, ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? parityTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: SelectionArea(child: child),
            ),
          ),
        ),
      ),
    );

Future<RenderedLine> renderLine(
  WidgetTester tester,
  String html, {
  required bool forceHtmlWidget,
  RenderSettings settings = const RenderSettings(fontSize: 20, lineHeight: 1.6),
  double width = 320,
  void Function(OpenedTab)? onOpenBook,
  void Function(int)? onNoteTap,
  void Function(String)? onAnchorTap,
  void Function(String, Offset)? onAnchorHover,
  void Function(String)? onAnchorHoverExit,
  void Function(String, Offset)? onTouchPreview,
  ThemeData? theme,
}) async {
  SmartTextWidget.debugForceHtmlWidget = forceHtmlWidget;
  final key = GlobalKey();
  try {
    await tester.pumpWidget(
      parityApp(
        SmartTextWidget(
          key: key,
          text: html,
          settings: settings,
          onOpenBook: onOpenBook,
          onNoteTap: onNoteTap,
          onAnchorTap: onAnchorTap,
          onAnchorHover: onAnchorHover,
          onAnchorHoverExit: onAnchorHoverExit,
          onTouchPreview: onTouchPreview,
        ),
        width: width,
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();
  } finally {
    SmartTextWidget.debugForceHtmlWidget = false;
  }
  final usedHtml = find
      .descendant(of: find.byKey(key), matching: find.byType(HtmlWidget))
      .evaluate()
      .isNotEmpty;
  final paragraphs = find
      .descendant(
        of: find.byKey(key),
        matching: find.byWidgetPredicate((w) => w is RichText),
      )
      .evaluate()
      .toList();
  final text = StringBuffer();
  final lines = <Rect>[];
  final carets = <Offset>[];
  final charStyles = <String>[];
  final rects = <Rect>[];
  for (final element in paragraphs) {
    final paragraph = element.renderObject! as RenderParagraph;
    final plain = paragraph.text.toPlainText();
    text.write(plain);
    // חלוקת התיבות תלויה בגבולות הספאנים, ולכן משווים את איחודן לכל שורה.
    final origin = paragraph.localToGlobal(Offset.zero);
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.length),
    )) {
      final rect = box.toRect().shift(origin);
      final index = lines.indexWhere(
        (line) => line.top == rect.top && line.bottom == rect.bottom,
      );
      if (index < 0) {
        lines.add(rect);
      } else {
        lines[index] = lines[index].expandToInclude(rect);
      }
    }
    for (var i = 0; i <= plain.length; i++) {
      carets.add(
        origin +
            paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero),
      );
    }
    _collect(paragraph.text, const TextStyle(), charStyles, []);
    rects.add(tester.getRect(find.byWidget(element.widget)));
  }
  final markers = <String>[];
  for (final overlay in tester.renderObjectList<RenderRaisedMarkerOverlay>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byType(RaisedMarkerOverlay),
    ),
  )) {
    for (final placement in overlay.debugPlacements()) {
      markers.add(
        '${placement.text}@${placement.anchorRect}->${placement.paintRect}',
      );
    }
  }
  return RenderedLine(
    usedHtmlWidget: usedHtml,
    size: tester.getSize(find.byKey(key)),
    text: text.toString(),
    paragraphs: rects,
    lines: lines,
    carets: carets,
    charStyles: charStyles,
    markers: markers,
  );
}

/// משווה את שני המסלולים. [boxTolerance] — סטייה תת-פיקסלית מותרת (justify).
Future<RenderedLine> expectInlineParity(
  WidgetTester tester,
  String html, {
  RenderSettings settings = const RenderSettings(fontSize: 20, lineHeight: 1.6),
  double width = 320,
  bool withCallbacks = true,
  double boxTolerance = 0,
  ThemeData? theme,
}) async {
  Future<RenderedLine> render(bool force) => renderLine(
    tester,
    html,
    forceHtmlWidget: force,
    settings: settings,
    width: width,
    onOpenBook: withCallbacks ? (_) {} : null,
    onNoteTap: withCallbacks ? (_) {} : null,
    onAnchorTap: withCallbacks ? (_) {} : null,
    onAnchorHover: withCallbacks ? (_, _) {} : null,
    onAnchorHoverExit: withCallbacks ? (_) {} : null,
    theme: theme,
  );
  final fast = await render(false);
  final reference = await render(true);
  expect(fast.usedHtmlWidget, isFalse, reason: 'מסלול הספאנים: $html');
  expect(reference.usedHtmlWidget, isTrue, reason: 'ייחוס: $html');
  expect(fast.text, reference.text, reason: html);
  expect(fast.size, reference.size, reason: html);
  expect(fast.paragraphs, reference.paragraphs, reason: html);
  expect(fast.lines.length, reference.lines.length, reason: html);
  for (var i = 0; i < fast.lines.length; i++) {
    final a = fast.lines[i];
    final b = reference.lines[i];
    expect(
      (a.left - b.left).abs() <= boxTolerance &&
          (a.right - b.right).abs() <= boxTolerance &&
          a.top == b.top &&
          a.bottom == b.bottom,
      isTrue,
      reason: '$html\nline $i: $a != $b',
    );
  }
  expect(fast.carets.length, reference.carets.length, reason: html);
  for (var i = 0; i < fast.carets.length; i++) {
    final a = fast.carets[i];
    final b = reference.carets[i];
    expect(
      (a.dx - b.dx).abs() <= boxTolerance && a.dy == b.dy,
      isTrue,
      reason: '$html\ncaret $i: $a != $b',
    );
  }
  expect(fast.charStyles.length, reference.charStyles.length, reason: html);
  for (var i = 0; i < fast.charStyles.length; i++) {
    if (fast.charStyles[i] != reference.charStyles[i]) {
      fail(
        '$html\nchar $i "${fast.text.substring(i, i + 1)}":\n'
        ' fast: ${fast.charStyles[i]}\n html: ${reference.charStyles[i]}',
      );
    }
  }
  expect(fast.markers, reference.markers, reason: html);
  return fast;
}

/// ה-recognizer של התו הראשון של [needle] בשורה.
TapGestureRecognizer? recognizerAt(WidgetTester tester, String needle) {
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byWidgetPredicate((w) => w is RichText),
  )) {
    final plain = paragraph.text.toPlainText();
    final index = plain.indexOf(needle);
    if (index < 0) continue;
    final span = paragraph.text.getSpanForPosition(TextPosition(offset: index));
    if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
      return span.recognizer! as TapGestureRecognizer;
    }
  }
  return null;
}
