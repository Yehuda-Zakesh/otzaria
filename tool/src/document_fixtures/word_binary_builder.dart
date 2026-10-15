import 'dart:typed_data';

import 'cfb_builder.dart';

/// חתיכת טקסט אחת כפי ש-Word שומר אותה ב-piece table.
///
/// [compressed] מדמה קטע שנכנס ל-cp1252 (בית לתו); אחרת הקטע נשמר כ-UTF-16 —
/// וזה המסלול שבו עברית תמיד עוברת, כי אינה נכנסת ל-cp1252.
class WordPiece {
  final String text;
  final bool compressed;

  const WordPiece(this.text, {this.compressed = false});
}

/// בונה מסמך Word בינארי (.doc / .dot) תקין: מכולת CFB עם זרם
/// `WordDocument` שבראשו FIB, וזרם `1Table` עם CLX ו-piece table אמיתיים.
///
/// **מקור יחיד** למחולל הקורפוס ולבדיקות — ראו [CfbBuilder].
/// [footnotes] הן טקסט ההערות לפי הסדר, ו-[footnoteRefs] הן מיקומי הסימנים
/// שלהן בגוף (CP). [footnoteNumberFormat] הוא קוד MSONFC שנכתב כ-
/// `sprmSNfcFtnRef` במאפייני הסקציה הראשונה.
Uint8List buildWordBinary(
  List<WordPiece> pieces, {
  bool template = false,
  bool encrypted = false,
  int wIdent = 0xA5EC,
  int nFib = 193,
  int? ccpTextOverride,
  bool omitClx = false,
  bool omitTableStream = false,
  bool useTable1 = true,
  int? outOfRangePiece,
  List<String> footnotes = const [],
  List<int> footnoteRefs = const [],
  int? footnoteNumberFormat,
}) {
  const textBase = 0x800; // אחרי ה-FIB, בגבול נוח

  // תת-מסמך ההערות יושב באותו piece table מיד אחרי הגוף, וכל הערה
  // היא פסקה בפני עצמה.
  final footnoteText = footnotes.map((text) => '$text\r').join();
  final allPieces = footnoteText.isEmpty
      ? pieces
      : [...pieces, WordPiece(footnoteText)];

  final body = BytesBuilder();
  final offsets = <int>[];
  final counts = <int>[];
  for (final piece in allPieces) {
    offsets.add(textBase + body.length);
    counts.add(piece.text.length);
    body.add(
      piece.compressed
          ? Uint8List.fromList(piece.text.codeUnits)
          : _utf16(piece.text),
    );
  }
  final bodyBytes = body.takeBytes();
  final totalCharacters = counts.fold<int>(0, (a, b) => a + b);
  final ccpText = ccpTextOverride ?? totalCharacters - footnoteText.length;

  // מדמה קובץ קטוע: ההיסט הפיזי של החתיכה מפנה מחוץ לזרם `WordDocument`.
  if (outOfRangePiece != null && outOfRangePiece < offsets.length) {
    offsets[outOfRangePiece] = 0x1FFFFF00;
  }

  final clx = _buildClx(allPieces, offsets, counts);
  const clxOffset = 64; // ריפוד לפני ה-CLX, כמו בקבצים אמיתיים

  // ה-SEPX של הסקציה יושב בזרם `WordDocument` (ולא בטבלה) — מיד אחרי הטקסט.
  final sepx = footnoteNumberFormat == null
      ? Uint8List(0)
      : _buildSepx(footnoteNumberFormat);
  final sepxOffset = textBase + bodyBytes.length;

  final table = _buildTableStream(
    clx: omitClx ? Uint8List(0) : clx,
    clxOffset: clxOffset,
    footnoteCount: footnotes.length,
    footnoteRefs: footnoteRefs,
    footnoteLengths: footnotes.map((text) => text.length + 1).toList(),
    ccpText: ccpText,
    hasSection: sepx.isNotEmpty,
    sepxOffset: sepxOffset,
  );

  final wordDocument = Uint8List(textBase + bodyBytes.length + sepx.length)
    ..setRange(textBase, textBase + bodyBytes.length, bodyBytes)
    ..setRange(sepxOffset, sepxOffset + sepx.length, sepx);
  _writeFib(
    wordDocument,
    wIdent: wIdent,
    nFib: nFib,
    template: template,
    encrypted: encrypted,
    useTable1: useTable1,
    ccpText: ccpText,
    ccpFtn: footnoteText.length,
    fcClx: omitClx ? 0 : clxOffset,
    lcbClx: omitClx ? 0 : clx.length,
    pointers: table.pointers,
  );

  return CfbBuilder({
    'WordDocument': wordDocument,
    if (!omitTableStream) (useTable1 ? '1Table' : '0Table'): table.bytes,
  }).build();
}

/// זרם הטבלה ומצביעי ה-FIB אל המבנים שבתוכו.
class _TableStream {
  final Uint8List bytes;

  /// אינדקס ב-`fibRgFcLcb` → (fc, lcb).
  final Map<int, (int, int)> pointers;

  const _TableStream(this.bytes, this.pointers);
}

/// בונה את זרם הטבלה: CLX, ולצדו ה-PLC-ים של ההערות ושל הסקציות.
_TableStream _buildTableStream({
  required Uint8List clx,
  required int clxOffset,
  required int footnoteCount,
  required List<int> footnoteRefs,
  required List<int> footnoteLengths,
  required int ccpText,
  required bool hasSection,
  required int sepxOffset,
}) {
  final out = BytesBuilder()..add(Uint8List(clxOffset));
  out.add(clx);
  final pointers = <int, (int, int)>{};

  void align() {
    if (out.length % 4 != 0) out.add(Uint8List(4 - out.length % 4));
  }

  if (footnoteCount > 0) {
    // PlcffndRef: (n+1) מיקומי CP בגוף, ואחריהם n מבני FRD בני 2 בתים.
    align();
    final refs = Uint8List(4 * (footnoteCount + 1) + 2 * footnoteCount);
    final refsView = ByteData.sublistView(refs);
    for (var i = 0; i < footnoteCount; i++) {
      refsView.setUint32(
        i * 4,
        i < footnoteRefs.length ? footnoteRefs[i] : 0,
        Endian.little,
      );
    }
    refsView.setUint32(footnoteCount * 4, ccpText, Endian.little);
    pointers[_plcffndRefIndex] = (out.length, refs.length);
    out.add(refs);

    // PlcffndTxt: גבולות הטקסט של כל הערה, יחסית לתחילת תת-המסמך.
    align();
    final texts = Uint8List(4 * (footnoteCount + 1));
    final textsView = ByteData.sublistView(texts);
    var cp = 0;
    for (var i = 0; i < footnoteCount; i++) {
      textsView.setUint32(i * 4, cp, Endian.little);
      cp += footnoteLengths[i];
    }
    textsView.setUint32(footnoteCount * 4, cp, Endian.little);
    pointers[_plcffndTxtIndex] = (out.length, texts.length);
    out.add(texts);
  }

  if (hasSection) {
    // PlcfSed: שני מיקומי CP ומבנה SED בן 12 בתים, שבו fcSepx הוא השדה השני.
    align();
    final sed = Uint8List(4 * 2 + 12);
    final sedView = ByteData.sublistView(sed);
    sedView.setUint32(0, 0, Endian.little);
    sedView.setUint32(4, ccpText, Endian.little);
    sedView.setUint32(8 + 2, sepxOffset, Endian.little);
    pointers[_plcfSedIndex] = (out.length, sed.length);
    out.add(sed);
  }

  return _TableStream(out.takeBytes(), pointers);
}

/// SEPX עם `sprmSNfcFtnRef` בלבד: `cb` בן שני בתים, ואחריו ה-grpprl.
Uint8List _buildSepx(int msonfc) {
  final sepx = Uint8List(5);
  final view = ByteData.sublistView(sepx);
  view.setUint16(0, 3, Endian.little); // cb
  view.setUint16(2, 0x3009, Endian.little); // sprmSNfcFtnRef
  sepx[4] = msonfc;
  return sepx;
}

/// אינדקסים ב-`fibRgFcLcb`, כמו בצד הקורא.
const int _plcffndRefIndex = 2;
const int _plcffndTxtIndex = 3;
const int _plcfSedIndex = 6;

Uint8List _utf16(String text) {
  final bytes = Uint8List(text.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < text.length; i++) {
    view.setUint16(i * 2, text.codeUnitAt(i), Endian.little);
  }
  return bytes;
}

/// CLX = Pcdt עם PlcPcd: (n+1) מיקומי CP ואחריהם n מתארי חתיכה בני 8 בתים.
Uint8List _buildClx(
  List<WordPiece> pieces,
  List<int> offsets,
  List<int> counts,
) {
  final n = pieces.length;
  final plc = Uint8List(4 * (n + 1) + 8 * n);
  final view = ByteData.sublistView(plc);

  var cp = 0;
  for (var i = 0; i < n; i++) {
    view.setUint32(i * 4, cp, Endian.little);
    cp += counts[i];
  }
  view.setUint32(n * 4, cp, Endian.little);

  final pcdBase = (n + 1) * 4;
  for (var i = 0; i < n; i++) {
    // ההיסט של חתיכה דחוסה נשמר כפול, וסיבית 30 מסמנת את הדחיסה.
    final fc = pieces[i].compressed
        ? (offsets[i] * 2) | 0x40000000
        : offsets[i];
    view.setUint32(pcdBase + i * 8 + 2, fc, Endian.little);
  }

  final out = BytesBuilder()..addByte(0x02); // clxt = Pcdt
  final size = Uint8List(4);
  ByteData.sublistView(size).setUint32(0, plc.length, Endian.little);
  return (out
        ..add(size)
        ..add(plc))
      .takeBytes();
}

/// כותב FIB במבנה משתנה-אורך: כל קטע מצהיר על גודלו ממש לפניו.
void _writeFib(
  Uint8List stream, {
  required int wIdent,
  required int nFib,
  required bool template,
  required bool encrypted,
  required bool useTable1,
  required int ccpText,
  required int ccpFtn,
  required int fcClx,
  required int lcbClx,
  required Map<int, (int, int)> pointers,
}) {
  const csw = 14;
  const cslw = 22;
  const cbRgFcLcb = 93;

  final view = ByteData.sublistView(stream);
  view.setUint16(0x00, wIdent, Endian.little);
  view.setUint16(0x02, nFib, Endian.little);
  view.setUint16(0x06, 0x040D, Endian.little); // lid: עברית

  var flags = 0;
  if (useTable1) flags |= 0x0200; // fWhichTblStm
  if (template) flags |= 0x0001; // fDot
  if (encrypted) flags |= 0x0100; // fEncrypted
  view.setUint16(0x0A, flags, Endian.little);

  view.setUint16(0x20, csw, Endian.little);
  final cslwOffset = 0x22 + csw * 2;
  view.setUint16(cslwOffset, cslw, Endian.little);

  final fibRgLwOffset = cslwOffset + 2;
  view.setUint32(fibRgLwOffset + 3 * 4, ccpText, Endian.little);

  final cbRgFcLcbOffset = fibRgLwOffset + cslw * 4;
  view.setUint16(cbRgFcLcbOffset, cbRgFcLcb, Endian.little);

  // ccpFtn הוא הערך החמישי ב-fibRgLw, מיד אחרי ccpText.
  view.setUint32(fibRgLwOffset + 4 * 4, ccpFtn, Endian.little);

  // fcClx/lcbClx הם הזוג ה-34 (אינדקס 33) בטבלת המצביעים.
  final pairsBase = cbRgFcLcbOffset + 2;
  final clxPair = pairsBase + 33 * 8;
  view.setUint32(clxPair, fcClx, Endian.little);
  view.setUint32(clxPair + 4, lcbClx, Endian.little);

  pointers.forEach((index, pair) {
    final base = pairsBase + index * 8;
    view.setUint32(base, pair.$1, Endian.little);
    view.setUint32(base + 4, pair.$2, Endian.little);
  });
}
