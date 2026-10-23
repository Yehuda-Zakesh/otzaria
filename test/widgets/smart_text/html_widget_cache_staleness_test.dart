import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// HtmlWidget שומר את העץ שנבנה כל עוד ה-html וה-textStyle זהים; צבעי הנושא
// וה-callbacks של SmartTextWidget חייבים בכל זאת להגיע לעץ הקיים.
const _markerHtml =
    'טקסט <a class="numbered-note-marker" href="otzaria://note-marker?id=1">(9)</a>';
const _noteHtml = 'טקסט <a href="otzaria://note?line=3">הערה</a>';

Widget _app({required Color primary, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(colorScheme: ColorScheme.light(primary: primary)),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );
}

TextSpan _spanWithText(WidgetTester tester, String text) {
  TextSpan? found;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return found == null;
    });
  }
  return found!;
}

void main() {
  for (final viaHtml in [true, false]) {
    testWidgets(
      'החלפת נושא בלי שינוי html צובעת מחדש את סמן-המספר'
      '${viaHtml ? '' : ' (מסלול הספאנים)'}',
      (tester) async {
        SmartTextWidget.debugForceHtmlWidget = viaHtml;
        addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
        const red = Color(0xFFCC0000);
        const blue = Color(0xFF0000CC);
        Widget build(Color primary) => _app(
          primary: primary,
          child: const SmartTextWidget(
            text: _markerHtml,
            settings: RenderSettings(fontSize: 20),
          ),
        );

        await tester.pumpWidget(build(red));
        expect(
          find.byType(HtmlWidget),
          viaHtml ? findsOneWidget : findsNothing,
        );
        expect(_spanWithText(tester, '(9)').style?.color, red);

        await tester.pumpWidget(build(blue));
        await tester.pumpAndSettle();
        expect(_spanWithText(tester, '(9)').style?.color, blue);
      },
    );
  }

  testWidgets('החלפת onNoteTap בלי שינוי html מפעילה את ה-callback החדש', (
    tester,
  ) async {
    final calls = <String>[];
    Widget build(String tag) => _app(
      primary: Colors.blue,
      child: SmartTextWidget(
        text: _noteHtml,
        settings: const RenderSettings(fontSize: 20),
        onNoteTap: (line) => calls.add('$tag:$line'),
      ),
    );

    await tester.pumpWidget(build('old'));
    await tester.pumpWidget(build('new'));

    final recognizer =
        _spanWithText(tester, 'הערה').recognizer! as TapGestureRecognizer;
    recognizer.onTap!();
    await tester.pumpAndSettle();

    expect(calls, ['new:3']);
  });

  testWidgets('החלפת onAnchorHover בלי שינוי html מפעילה את ה-callback החדש', (
    tester,
  ) async {
    final calls = <String>[];
    Widget build(String tag) => _app(
      primary: Colors.blue,
      child: SmartTextWidget(
        text: _markerHtml,
        settings: const RenderSettings(fontSize: 20),
        onAnchorHover: (url, _) => calls.add(tag),
      ),
    );

    await tester.pumpWidget(build('old'));
    await tester.pumpWidget(build('new'));

    _spanWithText(tester, '(9)').onEnter!(const PointerEnterEvent());
    expect(calls, ['new']);
  });
}
