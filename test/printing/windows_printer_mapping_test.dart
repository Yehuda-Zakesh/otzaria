import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/windows_print_native.dart';
import 'package:win32/win32.dart';

void main() {
  test('פרטי המדפסת וברירת המחדל תואמים למיפוי של printing', () {
    using((arena) {
      final info = arena<PRINTER_INFO_2>().ref
        ..pPrinterName = PWSTR('מדפסת רשת'.toNativeUtf16(allocator: arena))
        ..pDriverName = PWSTR('דרייבר'.toNativeUtf16(allocator: arena))
        ..pLocation = PWSTR('קומה שנייה'.toNativeUtf16(allocator: arena))
        ..pComment = PWSTR('הערה'.toNativeUtf16(allocator: arena));
      expect(windowsPrinterFromInfo(info, 'מדפסת רשת').toMap(), {
        'url': 'מדפסת רשת',
        'name': 'מדפסת רשת',
        'model': 'דרייבר',
        'location': 'קומה שנייה',
        'comment': 'הערה',
        'default': true,
        'available': true,
      });
      expect(windowsPrinterFromInfo(info, null).isDefault, isFalse);
      expect(windowsPrinterFromInfo(info, 'מדפסת אחרת').isDefault, isFalse);
    });
  });

  test('שדות חסרים הופכים למחרוזות ריקות כמו ב-printing', () {
    using((arena) {
      final info = arena<PRINTER_INFO_2>().ref;
      expect(windowsPrinterFromInfo(info, null).toMap(), {
        'url': '',
        'name': '',
        'model': '',
        'location': '',
        'comment': '',
        'default': false,
        'available': true,
      });
    });
  });

  test('רק ארבעת דגלי השגיאה של printing מסמנים מדפסת כלא זמינה', () {
    using((arena) {
      final info = arena<PRINTER_INFO_2>().ref;
      for (var bit = 0; bit < 32; bit++) {
        info.Status = 1 << bit;
        expect(
          windowsPrinterFromInfo(info, null).isAvailable,
          ![0x1, 0x2, 0x80, 0x1000].contains(info.Status),
          reason: 'status=0x${info.Status.toRadixString(16)}',
        );
      }
      info.Status = 0x1083;
      expect(windowsPrinterFromInfo(info, null).isAvailable, isFalse);
    });
  });
}
