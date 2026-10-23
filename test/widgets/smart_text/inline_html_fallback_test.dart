import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';

import 'inline_parity_harness.dart';

void main() {
  const lines = [
    '<span style="background-color: currentcolor">שלום</span>',
    '<a href="https://example.com" style="background-color: currentcolor">שלום</a>',
  ];

  test('רקע currentcolor אינו נתמך בספאנים ומחזיר fallback גם אחרי מטמון', () {
    for (final html in lines) {
      for (var attempt = 0; attempt < 2; attempt++) {
        expect(
          InlineHtmlDocument.parseLine(html, const TextStyle(fontSize: 20)),
          isNull,
          reason: html,
        );
      }
    }
  });

  testWidgets('רקע currentcolor נבנה ב-HtmlWidget בלי שגיאה או אובדן טקסט', (
    tester,
  ) async {
    for (final html in lines) {
      final actual = await renderLine(tester, html, forceHtmlWidget: false);
      expect(tester.takeException(), isNull);
      final reference = await renderLine(tester, html, forceHtmlWidget: true);
      expect(actual.usedHtmlWidget, isTrue);
      expect(actual.text, 'שלום');
      expect(actual.text, reference.text);
      expect(actual.size, reference.size);
      expect(actual.charStyles, reference.charStyles);
    }
  });
}
