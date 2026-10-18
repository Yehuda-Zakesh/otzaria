import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:printing/printing.dart' show Printer;
import 'package:win32/win32.dart' as win32;

const int _printerStatusPaused = 0x1;
const int _printerStatusError = 0x2;
const int _printerStatusOffline = 0x80;
const int _printerStatusNotAvailable = 0x1000;

/// המדפסות המותקנות, באותו מבנה ועם אותם שדות כמו בחבילת printing.
List<Printer> listWindowsPrinters() {
  return using((arena) {
    final defaultName = _defaultPrinterName(arena);
    const flags = win32.PRINTER_ENUM_LOCAL | win32.PRINTER_ENUM_CONNECTIONS;
    final needed = arena<Uint32>();
    final returned = arena<Uint32>();
    win32.EnumPrinters(flags, null, 2, null, 0, needed, returned);
    if (needed.value == 0) return const [];
    final buffer = arena<Uint8>(needed.value);
    final ok = win32.EnumPrinters(
      flags,
      null,
      2,
      buffer,
      needed.value,
      needed,
      returned,
    ).value;
    if (!ok) return const [];
    final infos = buffer.cast<win32.PRINTER_INFO_2>();
    return [
      for (var i = 0; i < returned.value; i++)
        windowsPrinterFromInfo(infos[i], defaultName),
    ];
  });
}

/// ממפה נתוני Win32 לשדות המדפסת שמחזירה חבילת printing.
@visibleForTesting
Printer windowsPrinterFromInfo(win32.PRINTER_INFO_2 info, String? defaultName) {
  String text(win32.PWSTR value) =>
      value.address == 0 ? '' : value.toDartString();
  final name = text(info.pPrinterName);
  const unavailable =
      _printerStatusNotAvailable |
      _printerStatusError |
      _printerStatusOffline |
      _printerStatusPaused;
  return Printer(
    url: name,
    name: name,
    model: text(info.pDriverName),
    location: text(info.pLocation),
    comment: text(info.pComment),
    isDefault: name == defaultName,
    isAvailable: info.Status & unavailable == 0,
  );
}

String? _defaultPrinterName(Arena arena) {
  final size = arena<Uint32>();
  win32.GetDefaultPrinter(null, size);
  if (size.value == 0) return null;
  final name = arena<Uint16>(size.value).cast<Utf16>();
  if (!win32.GetDefaultPrinter(win32.PWSTR(name), size)) return null;
  return name.toDartString();
}
