import 'dart:typed_data';

import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';

/// קורא מכולת Compound File Binary (CFB/OLE2) — מערכת-הקבצים הזעירה
/// שבתוכה מיקרוסופט אורזת מסמכי Office ישנים (.doc, .xls, .msg).
///
/// הרכיב גנרי ואינו יודע דבר על Word: הוא מספק גישה ל-streams לפי שם, וזהו.
/// כך הוא נבדק בפני עצמו ומשמש גם את זיהוי ה-WBK — שצריך להבחין בין גיבוי
/// של Word לבין קובץ OLE אחר ששמו שונה.
///
/// ראו `docs/legacy_word_doc_research.md` לרקע ולתכנית המימוש.
class CfbFile {
  CfbFile._({
    required this._bytes,
    required this._sectorSize,
    required this._fat,
    required this._miniFat,
    required this._entries,
    required this._miniStream,
    required this._format,
    required this._path,
  });

  final Uint8List _bytes;
  final int _sectorSize;
  final List<int> _fat;
  final List<int> _miniFat;
  final List<CfbEntry> _entries;
  final Uint8List _miniStream;
  final DocumentFormat? _format;
  final String? _path;

  /// חתימת CFB בתחילת הקובץ.
  static const List<int> signature = [
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
  ];

  static const int _endOfChain = 0xFFFFFFFE;
  static const int _freeSector = 0xFFFFFFFF;
  static const int _miniSectorSize = 64;
  static const int _directoryEntrySize = 128;

  /// גודל ה-mini stream cutoff. המפרט מקבע אותו, ולכן הוא נלקח מכאן ולא
  /// מהשדה שבכותר: ערך מזויף שם היה מפנה *כל* זרם למקום הלא נכון בקובץ,
  /// ואילו אכיפה של הערך הייתה דוחה קובץ שכל השאר בו תקין.
  static const int _miniStreamCutoff = 0x1000;

  /// האם הבייטים פותחים בחתימת CFB. בדיקה זולה לפני ניסיון פענוח מלא.
  static bool hasSignature(Uint8List bytes) => hasOleContainerSignature(bytes);

  /// מפרסר את המכולה. זורק [CorruptedDocumentException] על מבנה שבור.
  ///
  /// [format] ו-[path] נשמרים בחריגה בלבד, לצורכי לוג ודיווח.
  factory CfbFile.parse(
    Uint8List bytes, {
    DocumentFormat? format,
    String? path,
  }) {
    Never fail(String reason) => throw CorruptedDocumentException(
      path: path,
      format: format,
      cause: reason,
    );

    if (!hasSignature(bytes)) fail('חתימת CFB חסרה');
    if (bytes.length < 512) fail('הקובץ קצר מ-header של CFB');

    final data = ByteData.sublistView(bytes);

    if (data.getUint16(0x1C, Endian.little) != 0xFFFE) {
      fail('סדר בתים לא נתמך');
    }

    final sectorShift = data.getUint16(0x1E, Endian.little);
    if (sectorShift != 9 && sectorShift != 12) {
      fail('גודל סקטור לא נתמך (shift=$sectorShift)');
    }
    final sectorSize = 1 << sectorShift;

    if (data.getUint16(0x20, Endian.little) != 6) {
      fail('גודל mini-sector לא נתמך');
    }

    final fatSectorCount = data.getUint32(0x2C, Endian.little);
    final firstDirSector = data.getUint32(0x30, Endian.little);
    final firstMiniFatSector = data.getUint32(0x3C, Endian.little);
    final firstDifatSector = data.getUint32(0x44, Endian.little);

    final maxSector = (bytes.length ~/ sectorSize) + 1;

    int sectorOffset(int sector) => (sector + 1) * sectorSize;

    void requireSector(int sector) {
      if (sector < 0 || sectorOffset(sector) + sectorSize > bytes.length) {
        fail('הפניה לסקטור $sector מחוץ לקובץ');
      }
    }

    // ה-FAT מתאר את סקטורי הקובץ עצמו, ולכן מספר סקטוריו חסום בגודלו. בלי
    // החסימה כותר משקר מנפח את `fat` לג'יגה-בייטים לפני שמישהו קורא ממנו.
    final maxFatSectors = (maxSector * 4 / sectorSize).ceil() + 1;
    if (fatSectorCount > maxFatSectors) {
      fail('הכותר מצהיר על $fatSectorCount סקטורי FAT — יותר מהאפשרי');
    }

    // ── DIFAT → רשימת סקטורי ה-FAT ──────────────────────────────────────
    final fatSectors = <int>[];
    for (var i = 0; i < 109 && fatSectors.length < fatSectorCount; i++) {
      final sector = data.getUint32(0x4C + i * 4, Endian.little);
      if (sector == _freeSector) break;
      fatSectors.add(sector);
    }

    var difatSector = firstDifatSector;
    final difatVisited = <int>{};
    while (difatSector != _endOfChain &&
        difatSector != _freeSector &&
        fatSectors.length < fatSectorCount) {
      // רק הגנת-מעגל. אורך השרשרת חסום כבר ע"י `fatSectorCount` בתנאי הלולאה,
      // ואכיפה של `difatSectorCount` הייתה דוחה כל .doc גדול שכותרו מצהיר
      // עליו בחסר — טעות נפוצה בכותבים שאינם Word.
      if (!difatVisited.add(difatSector)) fail('שרשרת DIFAT מעגלית');
      requireSector(difatSector);
      final base = sectorOffset(difatSector);
      final entriesPerSector = sectorSize ~/ 4;
      // עצירה ב-`fatSectorCount` גם כאן: בלעדיה סקטור DIFAT בודד מוסיף 127
      // כניסות שגויות, שהופכות סקטורים לא-חוקיים ל"חוקיים" ב-FAT.
      for (
        var i = 0;
        i < entriesPerSector - 1 && fatSectors.length < fatSectorCount;
        i++
      ) {
        final sector = data.getUint32(base + i * 4, Endian.little);
        if (sector == _freeSector || sector == _endOfChain) continue;
        fatSectors.add(sector);
      }
      difatSector = data.getUint32(
        base + (entriesPerSector - 1) * 4,
        Endian.little,
      );
    }

    // ── FAT ──────────────────────────────────────────────────────────────
    final fat = <int>[];
    for (final sector in fatSectors) {
      requireSector(sector);
      final base = sectorOffset(sector);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(data.getUint32(base + i * 4, Endian.little));
      }
    }
    if (fat.isEmpty) fail('טבלת FAT ריקה');

    /// אוסף את בייטי השרשרת המתחילה ב-[start]. שומר על מונה עצירה — שרשרת
    /// מעגלית בקובץ פגום הייתה תוקעת את ההמרה לנצח.
    ///
    /// [minLength] מאמת שהשרשרת מכסה את הגודל שהוצהר: שרשרת שנגמרה לפניו היא
    /// קובץ קטוע, ושתיקה כאן הייתה מייצרת "ספר תקין" חסר-תוכן שנכנס למטמון
    /// ולאינדקס. הבייטים העודפים בסקטור האחרון **אינם** נחתכים — זרם זעיר
    /// שיושב בסופו של ה-mini stream חורג מ-`root.size` שהוצהר בחסר.
    Uint8List readChain(int start, {int? minLength}) {
      final builder = BytesBuilder(copy: false);
      var sector = start;
      var guard = 0;
      final visited = <int>{};
      while (sector != _endOfChain && sector != _freeSector) {
        if (sector < 0 || sector >= fat.length) {
          fail('סקטור $sector אינו ב-FAT');
        }
        if (!visited.add(sector)) fail('שרשרת סקטורים מעגלית');
        if (guard++ > maxSector) fail('שרשרת סקטורים ארוכה מדי');
        requireSector(sector);
        final base = sectorOffset(sector);
        builder.add(Uint8List.sublistView(bytes, base, base + sectorSize));
        sector = fat[sector];
      }
      final result = builder.takeBytes();
      if (minLength != null && result.length < minLength) {
        fail('שרשרת סקטורים נגמרה אחרי ${result.length} מתוך $minLength בתים');
      }
      return result;
    }

    // ── miniFAT ──────────────────────────────────────────────────────────
    final miniFat = <int>[];
    if (firstMiniFatSector != _endOfChain &&
        firstMiniFatSector != _freeSector) {
      final raw = readChain(firstMiniFatSector);
      final view = ByteData.sublistView(raw);
      for (var i = 0; i + 4 <= raw.length; i += 4) {
        miniFat.add(view.getUint32(i, Endian.little));
      }
    }

    // ── ספריות ───────────────────────────────────────────────────────────
    if (firstDirSector == _endOfChain || firstDirSector == _freeSector) {
      fail('אין סקטור ספריות');
    }
    final dirBytes = readChain(firstDirSector);
    final dirView = ByteData.sublistView(dirBytes);

    // שלב 1: קריאת כל משבצות הספרייה *לפי מיקומן*. משבצת פנויה נשמרת כ-null
    // ואינה מדולגת — מזהי האחים מפנים למיקום, ודילוג היה מזיז את כל המפתחות.
    final slots = <CfbEntry?>[];
    for (
      var offset = 0;
      offset + _directoryEntrySize <= dirBytes.length;
      offset += _directoryEntrySize
    ) {
      final type = dirBytes[offset + 66];
      final nameBytes = dirView.getUint16(offset + 64, Endian.little);
      if ((type != 1 && type != 2 && type != 5) ||
          nameBytes < 2 ||
          nameBytes > 64) {
        slots.add(null);
        continue;
      }

      final units = <int>[];
      for (var i = 0; i + 1 < nameBytes - 2; i += 2) {
        units.add(dirView.getUint16(offset + i, Endian.little));
      }

      slots.add(
        CfbEntry(
          name: String.fromCharCodes(units),
          isStream: type == 2,
          isRoot: type == 5,
          startSector: dirView.getUint32(offset + 116, Endian.little),
          // גודל 64 סיביות; החלק העליון אפס בקבצי v3.
          size: dirView.getUint32(offset + 120, Endian.little),
          leftId: dirView.getUint32(offset + 68, Endian.little),
          rightId: dirView.getUint32(offset + 72, Endian.little),
          childId: dirView.getUint32(offset + 76, Endian.little),
        ),
      );
    }

    // שלב 2: הליכה על עץ הילדים הישירים של השורש בלבד.
    //
    // הספרייה היא עץ, לא רשימה. מסמך עם אובייקט OLE מוטמע מכיל `WordDocument`
    // ו-`1Table` *פעמיים* — פעם ברמת השורש ופעם בתוך ה-storage של האובייקט.
    // סריקה שטוחה הייתה מזווגת זרם ראשי עם טבלה של האובייקט המוטמע.
    final rootSlot = slots.firstWhere(
      (e) => e?.isRoot ?? false,
      orElse: () => null,
    );
    if (rootSlot == null) fail('אין רשומת שורש');

    //
    // ההליכה איטרטיבית ולא רקורסיבית: עומק העץ שווה למספר המשבצות, ושרשרת
    // `leftId` ליניארית בת עשרות אלפים (חוקית) הייתה מקריסה את המחסנית.
    final entries = <CfbEntry>[rootSlot];
    final visited = <int>{};
    // `expanded` מסמן שתת-העץ השמאלי כבר טופל — כך נשמר סדר in-order.
    final pending = <(int, bool)>[(rootSlot.childId, false)];
    while (pending.isNotEmpty) {
      final (id, expanded) = pending.removeLast();
      if (id >= slots.length) continue;
      final entry = slots[id];
      if (entry == null) continue;
      if (expanded) {
        entries.add(entry);
        pending.add((entry.rightId, false));
        continue;
      }
      if (!visited.add(id)) continue;
      pending.add((id, true));
      pending.add((entry.leftId, false));
    }

    // ── mini stream (זרם השורש) ──────────────────────────────────────────
    final root = entries.firstWhere(
      (e) => e.isRoot,
      orElse: () => fail('אין רשומת שורש'),
    );
    final miniStream = root.size == 0
        ? Uint8List(0)
        : readChain(root.startSector, minLength: root.size);

    return CfbFile._(
      bytes: bytes,
      sectorSize: sectorSize,
      fat: fat,
      miniFat: miniFat,
      entries: entries,
      miniStream: miniStream,
      format: format,
      path: path,
    );
  }

  Never _fail(String reason) => throw CorruptedDocumentException(
    path: _path,
    format: _format,
    cause: reason,
  );

  /// שמות ה-streams שבמכולה (ללא storages ורשומת השורש).
  List<String> get streamNames =>
      _entries.where((e) => e.isStream).map((e) => e.name).toList();

  /// האם קיים stream בשם [name] (השוואה ללא תלות ברישיות).
  bool hasStream(String name) => _findStream(name) != null;

  /// קורא stream לפי שם, או `null` אם אינו קיים.
  ///
  /// זרם קצר מ-`miniStreamCutoff` יושב ב-mini stream ומשורשר דרך ה-miniFAT;
  /// זרם גדול יושב בסקטורים רגילים. ההבחנה מוסתרת מהקורא.
  ///
  /// זורק [CorruptedDocumentException] כששרשרת הסקטורים שבורה או נגמרת לפני
  /// הגודל המוצהר — זרם חלקי היה נראה כמסמך תקין ופשוט קצר יותר.
  Uint8List? readStream(String name) {
    final entry = _findStream(name);
    if (entry == null) return null;
    if (entry.size == 0) return Uint8List(0);

    return _readChain(entry, mini: entry.size < _miniStreamCutoff);
  }

  CfbEntry? _findStream(String name) {
    final target = name.toLowerCase();
    for (final entry in _entries) {
      if (entry.isStream && entry.name.toLowerCase() == target) return entry;
    }
    return null;
  }

  /// קורא את שרשרת הסקטורים של [entry] במלואה.
  ///
  /// [mini] בוחר בין ה-miniFAT (זרמים קצרים, שיושבים בתוך זרם השורש) לבין
  /// ה-FAT הראשי. כל תקלה בשרשרת זורקת — ראו [readStream].
  Uint8List _readChain(CfbEntry entry, {required bool mini}) {
    final chain = mini ? _miniFat : _fat;
    final unit = mini ? _miniSectorSize : _sectorSize;
    final source = mini ? _miniStream : _bytes;
    final builder = BytesBuilder(copy: false);
    final visited = <int>{};
    var sector = entry.startSector;

    while (builder.length < entry.size) {
      if (sector == _endOfChain || sector == _freeSector) {
        _fail(
          'הזרם "${entry.name}" נגמר אחרי ${builder.length} '
          'מתוך ${entry.size} בתים',
        );
      }
      if (sector < 0 || sector >= chain.length) {
        _fail('הזרם "${entry.name}" מפנה לסקטור $sector שאינו בטבלה');
      }
      if (!visited.add(sector)) {
        _fail('שרשרת סקטורים מעגלית בזרם "${entry.name}"');
      }
      // ה-mini stream מתחיל בתחילת עצמו; סקטורי ה-FAT מוזזים בסקטור הכותר.
      final base = mini ? sector * unit : (sector + 1) * unit;
      if (base + unit > source.length) {
        _fail('הזרם "${entry.name}" מפנה לסקטור $sector מחוץ לקובץ');
      }
      builder.add(Uint8List.sublistView(source, base, base + unit));
      sector = chain[sector];
    }

    final bytes = builder.takeBytes();
    return bytes.length <= entry.size
        ? bytes
        : Uint8List.sublistView(bytes, 0, entry.size);
  }
}

/// רשומה בעץ הספריות של המכולה.
class CfbEntry {
  final String name;
  final bool isStream;
  final bool isRoot;
  final int startSector;
  final int size;

  /// מזהי האח השמאלי/הימני והילד הראשון בעץ האדום-שחור של הספרייה.
  /// `0xFFFFFFFF` מסמן היעדר.
  final int leftId;
  final int rightId;
  final int childId;

  const CfbEntry({
    required this.name,
    required this.isStream,
    required this.isRoot,
    required this.startSector,
    required this.size,
    this.leftId = 0xFFFFFFFF,
    this.rightId = 0xFFFFFFFF,
    this.childId = 0xFFFFFFFF,
  });

  @override
  String toString() => 'CfbEntry($name, stream: $isStream, size: $size)';
}

/// האם המכולה היא מסמך Word בינארי — קיום זרם `WordDocument`.
///
/// זו ההבחנה שחסרה לחתימת ה-OLE לבדה: .xls ו-.msg נושאים את אותה חתימה
/// בדיוק, וקובץ WBK יכול להיות כל אחד מהם.
bool isLegacyWordContainer(Uint8List bytes, {String? path}) {
  if (!CfbFile.hasSignature(bytes)) return false;
  try {
    return CfbFile.parse(bytes, path: path).hasStream('WordDocument');
  } on CorruptedDocumentException {
    return false;
  }
}
