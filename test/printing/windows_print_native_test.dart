@TestOn('windows')
library;

import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/windows_print_native.dart';

void main() {
  test('מניית המדפסות ב-isolate מחזירה לכל היותר ברירת מחדל אחת', () async {
    final printers = await Isolate.run(listWindowsPrinters);
    expect(printers.where((printer) => printer.isDefault).length, lessThan(2));
  });
}
