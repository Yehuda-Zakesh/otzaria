import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

void main() {
  const cases = [
    (
      'אות עברית מקודדת לפני ציטוט באנגלית',
      '&#1488; test.',
      'א test.',
      TextDirection.rtl,
    ),
    (
      'עברית אחרי פסקה אנגלית',
      '<p>English.</p><p>עברית.</p>',
      'עברית.',
      TextDirection.rtl,
    ),
    (
      'עברית עם ציטוט אנגלי במסלול המהיר',
      'עברית with English.',
      'עברית with English.',
      TextDirection.rtl,
    ),
    (
      'כיוון אנגלי מפורש',
      '<p dir="ltr">English.</p>',
      'English.',
      TextDirection.ltr,
    ),
    (
      'כיוון עברי מפורש לשורה מעורבת',
      '<p dir="rtl">English ועברית.</p>',
      'English ועברית.',
      TextDirection.rtl,
    ),
    (
      'פסקה עברית אחרי פסקה בעלת כיוון אנגלי מפורש',
      '<p dir="ltr">English.</p><p>עברית.</p>',
      'עברית.',
      TextDirection.rtl,
    ),
  ];

  for (final (description, html, plainText, direction) in cases) {
    testWidgets(description, (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SmartTextWidget(
                text: html,
                settings: const RenderSettings(fontSize: 20),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = find
          .byType(RichText)
          .evaluate()
          .map((element) => element.renderObject)
          .whereType<RenderParagraph>()
          .singleWhere(
            (paragraph) => paragraph.text.toPlainText() == plainText,
          );
      expect(paragraph.textDirection, direction);
    });
  }
}
