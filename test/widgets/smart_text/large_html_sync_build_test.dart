import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// שורת רשימה צריכה את גובהה האמיתי כבר בפריים הראשון, גם מעל סף ה-async של fwfh.
void main() {
  for (final viaHtml in [true, false]) {
    testWidgets(
      'HTML ארוך מ-kShouldBuildAsync נבנה בגובה מלא בפריים הראשון'
      '${viaHtml ? '' : ' (מסלול הספאנים)'}',
      (tester) async {
        SmartTextWidget.debugForceHtmlWidget = viaHtml;
        addTearDown(() => SmartTextWidget.debugForceHtmlWidget = false);
        final html =
            '${'מילה ' * (kShouldBuildAsync ~/ 4)}'
            '<a class="numbered-note-marker" href="otzaria://note-marker?id=1">(9)</a>';
        expect(html.length, greaterThan(kShouldBuildAsync));

        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SmartTextWidget(
                    text: html,
                    settings: const RenderSettings(fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        );

        SmartTextWidget.debugForceHtmlWidget = false;
        expect(
          find.byType(HtmlWidget),
          viaHtml ? findsOneWidget : findsNothing,
        );
        expect(find.byType(FutureBuilder<Widget>), findsNothing);
        expect(
          tester.getSize(find.byType(SmartTextWidget)).height,
          greaterThan(100),
        );
      },
    );
  }
}
