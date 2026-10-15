import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:otzaria/utils/file/docx_to_otzaria.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/zip_limits.dart';
import 'package:xml/xml.dart' as xml;

/// גרסת שכבת ה-XML עצמה: פריסת Flat OPC וקריאת WordML 2003.
/// **חובה להעלות בכל שינוי שמשפיע על הפלט.**
const int _wordXmlLayerVersion = 1;

/// גרסת ממיר ה-XML של Word — חלק ממפתח-התוקף של המטמון.
///
/// **נגזרת גם מגרסת מנוע ה-OOXML**, שהוא זה שמייצר את הפלט בפועל: קבוע
/// עצמאי היה נשאר מאחור בשקט בכל שינוי במנוע, והמטמון היה מגיש פלט מיושן.
const int kWordXmlConverterVersion =
    _wordXmlLayerVersion * 1000 + kOoxmlWordConverterVersion;

/// תקרת גודל לקובץ XML של Word. הפריסה מייצרת מחרוזות ומערכי בייטים בגודל
/// המסמך כולו, ולכן קובץ ענק היה מנפח את הזיכרון פי כמה.
const int _maxWordXmlBytes = 256 * 1024 * 1024;

/// ממיר מסמך Word שנשמר כ-XML לטקסט של אוצריא.
///
/// שני הדיאלקטים מגיעים בסופו של דבר לאותו מנוע Word: Flat OPC נפרס
/// ל-[Archive] זהה לחבילת DOCX, ו-WordML 2003 מרונדר ישירות מהמסמך.
String wordXmlToText(
  Uint8List bytes,
  String title, {
  bool embedImages = true,
}) {
  if (bytes.length > _maxWordXmlBytes) {
    throw CorruptedDocumentException(
      format: DocumentFormat.xml,
      cause: 'הקובץ גדול מ-${_maxWordXmlBytes ~/ (1024 * 1024)}MB',
    );
  }

  final xml.XmlDocument document;
  try {
    document = xml.XmlDocument.parse(_decodeXml(bytes));
  } catch (e) {
    throw CorruptedDocumentException(
      format: DocumentFormat.xml,
      cause: 'הקובץ אינו XML תקין: $e',
    );
  }

  final dialect = wordXmlDialectForRootName(document.rootElement.name.local);
  if (dialect == null) {
    throw UnsupportedDocumentFormatException(
      format: DocumentFormat.xml,
      cause: 'שורש ה-XML אינו מסמך Word (${document.rootElement.name.local})',
    );
  }

  return switch (dialect) {
    WordXmlDialect.wordMl2003 => wordMl2003ToText(
      document,
      title,
      format: DocumentFormat.xml,
      embedImages: embedImages,
    ),
    WordXmlDialect.flatOpc => ooxmlWordArchiveToText(
      _archiveFromFlatOpc(document),
      title,
      format: DocumentFormat.xml,
      embedImages: embedImages,
    ),
  };
}

/// בונה [Archive] מחבילת Flat OPC.
///
/// כל `pkg:part` הופך לרשומה בשם שלו: חלק XML נכתב כטקסט, וחלק בינארי
/// (`pkg:binaryData`) מפוענח מ-base64. התוצאה זהה במבנה לחבילת DOCX, ולכן
/// מנוע ה-OOXML אינו צריך לדעת מאין היא הגיעה.
Archive _archiveFromFlatOpc(xml.XmlDocument document) {
  final archive = Archive();
  for (final part in document.rootElement.childElements) {
    if (part.name.local != 'part') continue;
    final name = part.getAttribute('pkg:name') ?? part.getAttribute('name');
    if (name == null) continue;
    final entryName = name.startsWith('/') ? name.substring(1) : name;

    final binary = _childNamed(part, 'binaryData');
    if (binary != null) {
      // חלק בינארי פגום מדולג; תמונה אחת אינה שווה כשל של המסמך כולו.
      try {
        final data = base64Decode(binary.innerText.replaceAll(_whitespace, ''));
        archive.addFile(ArchiveFile(entryName, data.length, data));
      } catch (_) {
        continue;
      }
      continue;
    }

    final xmlData = _childNamed(part, 'xmlData');
    if (xmlData == null) continue;
    final inner = xmlData.childElements.firstOrNull;
    if (inner == null) continue;
    final bytes = utf8.encode(inner.toXmlString());
    archive.addFile(ArchiveFile(entryName, bytes.length, bytes));
  }

  if (archive.isEmpty) {
    throw CorruptedDocumentException(
      format: DocumentFormat.xml,
      cause: 'חבילת Flat OPC בלי אף pkg:part קריא',
    );
  }
  // אין כאן דחיסה, אך תקרת מספר הרשומות עדיין רלוונטית — קובץ עם עשרות
  // אלפי חלקים אינו מסמך.
  assertSafeArchive(archive, format: DocumentFormat.xml);
  return archive;
}

final RegExp _whitespace = RegExp(r'\s');

xml.XmlElement? _childNamed(xml.XmlElement parent, String localName) {
  for (final child in parent.childElements) {
    if (child.name.local == localName) return child;
  }
  return null;
}

/// Word כותב .xml ב-UTF-8, אך קובץ שנערך ידנית עלול להיות ב-latin1.
String _decodeXml(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}
