import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';

void main() {
  _nikudTests();
  for (final source in ['<br>אב', 'אב<br>', '<br>אב<br>']) {
    test('המרה סימטרית גם כשהתיקון הסיר את שולי $source', () {
      final controller = PluginCorrectionController(source);
      addTearDown(controller.dispose);
      for (final canonical in [controller.source.plain, 'אם', '', ' אמת ']) {
        expect(
          controller.forService(controller.forEditor(canonical)),
          canonical,
        );
      }
    });
  }

  test('עדכון מקור מסנכרן טקסט ושוליים גם כשהטקסט הגלוי זהה', () {
    final controller = PluginCorrectionController('<b>אב</b>');
    addTearDown(controller.dispose);
    controller.setSource('<p>אב</p>');
    expect(controller.text, 'אב');
    expect(controller.forService(controller.text), ' אב ');
    controller.setSource('<i>גד</i>');
    expect(controller.text, 'גד');
    expect(controller.forService(controller.text), 'גד');
  });

  test('הד חוזר של אותו מקור משמר בחירה ו-IME', () {
    const source = '<b>אב</b>';
    final controller = PluginCorrectionController(source);
    addTearDown(controller.dispose);
    const editing = TextEditingValue(
      text: 'אגב',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    controller.value = editing;
    controller.setSource(source);
    expect(controller.value, editing);
  });
}

void _nikudTests() {
  const base = 'שָׁלוֹם עוֹלָם';
  test('ספר ללא ניקוד: העורך מציג בלי ניקוד והמקור נשמר', () {
    final controller = PluginCorrectionController(base, hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.text, 'שלום עולם');
    expect(controller.forService(controller.text), base);
  });

  test('ספר ללא ניקוד: עריכה משמרת ניקוד של אותיות שלא נגעו בהן', () {
    final controller = PluginCorrectionController(base, hideNikud: true);
    addTearDown(controller.dispose);
    // הוספת תו בסוף "עולם": הניקוד של כל האותיות הקיימות נשאר.
    expect(
      controller.forService('שלום עולמם'),
      'שָׁלוֹם עוֹלָמם',
    );
    // הוספת תו בסוף המילה הראשונה אחרי האות המנוקדת.
    expect(controller.forService('שלומא עולם'), 'שָׁלוֹמא עוֹלָם');
    // מחיקת מילה שלמה.
    expect(controller.forService('שלום '), 'שָׁלוֹם ');
    // מחיקת הכול.
    expect(controller.forService(''), '');
  });

  test('ספר ללא ניקוד: מקף ופסק אינם נמחקים', () {
    final controller = PluginCorrectionController(
      'אָב־גָד ׀ הוּ',
      hideNikud: true,
    );
    addTearDown(controller.dispose);
    expect(controller.text, 'אב־גד ׀ הו');
  });

  test('ספר עם ניקוד: ללא שינוי התנהגות', () {
    final controller = PluginCorrectionController(base);
    addTearDown(controller.dispose);
    expect(controller.text, base);
    expect(controller.forService('x$base'), 'x$base');
  });

  test('forService טהורה ו-forEditor מעדכנת בסיס אחרי עריכה', () {
    final controller = PluginCorrectionController(base, hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.forService('שלום'), controller.forService('שלום'));
    final edited = controller.forService('שלום ');
    expect(controller.forEditor(edited), 'שלום ');
    expect(controller.forService('שלום ב'), 'שָׁלוֹם ב');
  });

  test('ניקוד שהוקלד בספר מוסתר אינו מוכפל ואינו משבש עריכות הבאות', () {
    final controller = PluginCorrectionController(
      'אָבֶג',
      hideNikud: true,
    );
    addTearDown(controller.dispose);
    // הדבקת קמץ נוסף אחרי האלף.
    expect(controller.forService('אָבג'), 'אָבֶג');
    expect(controller.forService('אבגד'), 'אָבֶגד');
  });

  test('surrogate pairs אינם נחתכים', () {
    final controller = PluginCorrectionController('א😀ב', hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.forService('א😁ב'), 'א😁ב');
  });
}
