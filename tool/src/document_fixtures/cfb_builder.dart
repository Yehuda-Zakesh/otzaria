import 'dart:typed_data';

/// בונה מכולת Compound File Binary (CFB/OLE2) גרסה 3, סקטור 512.
///
/// **מקור יחיד** לכל בניית CFB בפרויקט — גם למחולל הקורפוס וגם לבדיקות.
/// כשהיו שני מימושים, תיקון במבנה עץ הספרייה הוחל רק על אחד מהם והמחולל
/// המשיך לייצר קבצים שהקורא דוחה בצדק.
class CfbBuilder {
  static const int sectorSize = 512;
  static const int miniSectorSize = 64;
  static const int miniStreamCutoff = 4096;
  static const int _directoryEntrySize = 128;
  static const int endOfChain = 0xFFFFFFFE;
  static const int freeSector = 0xFFFFFFFF;
  static const int fatSector = 0xFFFFFFFD;
  static const int noEntry = 0xFFFFFFFF;

  static const List<int> signature = [
    0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
  ];

  /// זרמים ברמת השורש.
  final Map<String, Uint8List> streams;

  /// זרמים בתוך storage מוטמע (כמו אובייקט OLE בתוך מסמך Word). שמותיהם
  /// עשויים להתנגש עם שמות זרמי השורש — וזה בדיוק התרחיש שיש לבדוק.
  final Map<String, Uint8List> embedded;

  const CfbBuilder(this.streams, {this.embedded = const {}});

  Uint8List build() {
    // מפתח ייחודי לכל זרם: שם יכול לחזור בין השורש ל-storage המוטמע.
    final entries = <_Entry>[
      for (final e in streams.entries) _Entry('r:${e.key}', e.key, e.value),
      for (final e in embedded.entries)
        _Entry('e:${e.key}', e.key, e.value, inner: true),
    ];

    // 4 משבצות בסקטור. הספרייה נפרסת על פני כמה סקטורים כשצריך: קיצוצה
    // לסקטור אחד מחק בשקט את הרשומות המוטמעות, והבדיקה שאמורה לכסות אותן
    // רצה על קובץ שאין בו כלום.
    final directorySectors =
        (_directoryEntryCount(entries) * _directoryEntrySize +
            sectorSize -
            1) ~/
        sectorSize;

    final layout = _allocate(entries, directorySectors);
    final directory = _buildDirectory(entries, layout);

    final sectors = <Uint8List>[
      _fatSectorBytes(layout.fat),
      _fatSectorBytes(layout.miniFat),
      _padTo(directory, directorySectors * sectorSize),
      ...layout.contentSectors,
    ];

    return (BytesBuilder()
          ..add(_header(layout, directorySectors))
          ..add(_concat(sectors)))
        .takeBytes();
  }

  /// שורש + זרמי השורש + (ObjectPool + הזרמים המוטמעים), אם יש.
  static int _directoryEntryCount(List<_Entry> entries) {
    final inner = entries.where((e) => e.inner).length;
    return 1 + (entries.length - inner) + (inner == 0 ? 0 : 1 + inner);
  }

  // ── הקצאה ────────────────────────────────────────────────────────────────

  _Layout _allocate(List<_Entry> entries, int directorySectors) {
    // זרם קצר מ-`miniStreamCutoff` יושב ב-mini stream; ארוך — בסקטורים.
    final miniBuilder = BytesBuilder();
    final miniStart = <String, int>{};
    final miniCount = <String, int>{};
    for (final entry in entries) {
      if (entry.data.length >= miniStreamCutoff) continue;
      miniStart[entry.key] = miniBuilder.length ~/ miniSectorSize;
      miniBuilder.add(entry.data);
      final pad =
          (miniSectorSize - entry.data.length % miniSectorSize) %
          miniSectorSize;
      if (pad > 0) miniBuilder.add(Uint8List(pad));
      miniCount[entry.key] =
          (entry.data.length + miniSectorSize - 1) ~/ miniSectorSize;
    }
    final miniStream = miniBuilder.takeBytes();

    // סקטור 0=FAT, 1=miniFAT, ואחריהם סקטורי הספרייה; התוכן מתחיל אחריהם.
    final reserved = 2 + directorySectors;
    final content = <Uint8List>[];
    int addSectors(Uint8List data) {
      final first = reserved + content.length;
      for (var offset = 0; offset < data.length; offset += sectorSize) {
        final end = (offset + sectorSize).clamp(0, data.length);
        content.add(_padTo(data.sublist(offset, end), sectorSize));
      }
      return first;
    }

    final miniStreamStart = miniStream.isEmpty
        ? endOfChain
        : addSectors(miniStream);

    final bigStart = <String, int>{};
    for (final entry in entries) {
      if (entry.data.length < miniStreamCutoff) continue;
      bigStart[entry.key] = addSectors(entry.data);
    }

    // ה-FAT הוא סקטור אחד (128 כניסות) ולכן חוסם את הקובץ ל-~64KB. חריגה
    // זורקת ולא נחתכת בשקט: fixture שנחתך אינו נכשל אלא בודק פחות ממה
    // שנדמה. DIFAT וריבוי סקטורי FAT אינם נדרשים ל-fixtures.
    final fat = List<int>.filled(sectorSize ~/ 4, freeSector)
      ..[0] = fatSector
      ..[1] = endOfChain;

    void chain(int start, int byteLength) {
      final length = (byteLength + sectorSize - 1) ~/ sectorSize;
      if (start + length > fat.length) {
        throw StateError(
          'ה-fixture חורג מסקטור FAT יחיד (${(start + length) * sectorSize} '
          'בתים); יש לפצל אותו או להרחיב את הבונה',
        );
      }
      for (var i = 0; i < length; i++) {
        fat[start + i] = i == length - 1 ? endOfChain : start + i + 1;
      }
    }

    chain(2, directorySectors * sectorSize);
    if (miniStream.isNotEmpty) chain(miniStreamStart, miniStream.length);
    for (final entry in entries) {
      final start = bigStart[entry.key];
      if (start != null) chain(start, entry.data.length);
    }

    final miniFat = List<int>.filled(sectorSize ~/ 4, freeSector);
    miniStart.forEach((key, start) {
      final count = miniCount[key]!;
      for (var i = 0; i < count; i++) {
        miniFat[start + i] = i == count - 1 ? endOfChain : start + i + 1;
      }
    });

    return _Layout(
      contentSectors: content,
      fat: fat,
      miniFat: miniFat,
      miniStreamStart: miniStreamStart,
      miniStreamLength: miniStream.length,
      startSectorOf: (key) => miniStart[key] ?? bigStart[key]!,
    );
  }

  // ── ספריות ───────────────────────────────────────────────────────────────

  /// הספרייה היא **עץ**: השורש מצביע לילד הראשון, וכל ילד לאח הבא. עץ מנוון
  /// (רשימה מקושרת דרך `rightId`) חוקי לחלוטין למעבר, ופשוט לבנייה.
  Uint8List _buildDirectory(List<_Entry> entries, _Layout layout) {
    final root = entries.where((e) => !e.inner).toList();
    final inner = entries.where((e) => e.inner).toList();

    // מזהי משבצות: 0=שורש, 1..R=זרמי שורש, R+1=ObjectPool, R+2..=מוטמעים.
    final poolId = root.length + 1;
    final hasPool = inner.isNotEmpty;
    final firstChild = root.isEmpty ? (hasPool ? poolId : noEntry) : 1;

    final out = BytesBuilder()
      ..add(
        _directoryEntry(
          'Root Entry',
          type: _EntryType.root,
          startSector: layout.miniStreamStart,
          size: layout.miniStreamLength,
          childId: firstChild,
        ),
      );

    for (var i = 0; i < root.length; i++) {
      final isLast = i == root.length - 1;
      out.add(
        _directoryEntry(
          root[i].name,
          type: _EntryType.stream,
          startSector: layout.startSectorOf(root[i].key),
          size: root[i].data.length,
          rightId: isLast ? (hasPool ? poolId : noEntry) : i + 2,
        ),
      );
    }

    if (hasPool) {
      out.add(
        _directoryEntry(
          'ObjectPool',
          type: _EntryType.storage,
          startSector: 0,
          size: 0,
          childId: poolId + 1,
        ),
      );
      for (var i = 0; i < inner.length; i++) {
        final isLast = i == inner.length - 1;
        out.add(
          _directoryEntry(
            inner[i].name,
            type: _EntryType.stream,
            startSector: layout.startSectorOf(inner[i].key),
            size: inner[i].data.length,
            rightId: isLast ? noEntry : poolId + i + 2,
          ),
        );
      }
    }

    return out.takeBytes();
  }

  static Uint8List _directoryEntry(
    String name, {
    required int type,
    required int startSector,
    required int size,
    int leftId = noEntry,
    int rightId = noEntry,
    int childId = noEntry,
  }) {
    final entry = Uint8List(128);
    final view = ByteData.sublistView(entry);
    for (var i = 0; i < name.length && i < 31; i++) {
      view.setUint16(i * 2, name.codeUnitAt(i), Endian.little);
    }
    view.setUint16(64, (name.length + 1) * 2, Endian.little);
    entry[66] = type;
    entry[67] = 1; // color: black
    view.setUint32(68, leftId, Endian.little);
    view.setUint32(72, rightId, Endian.little);
    view.setUint32(76, childId, Endian.little);
    view.setUint32(116, startSector, Endian.little);
    view.setUint32(120, size, Endian.little);
    return entry;
  }

  // ── header ───────────────────────────────────────────────────────────────

  Uint8List _header(_Layout layout, int directorySectors) {
    final header = Uint8List(sectorSize)..setRange(0, 8, signature);
    final view = ByteData.sublistView(header);
    view.setUint16(0x18, 0x003E, Endian.little); // minor version
    view.setUint16(0x1A, 0x0003, Endian.little); // major version
    view.setUint16(0x1C, 0xFFFE, Endian.little); // byte order
    view.setUint16(0x1E, 9, Endian.little); // sector shift → 512
    view.setUint16(0x20, 6, Endian.little); // mini sector shift → 64
    view.setUint32(0x2C, 1, Endian.little); // FAT sector count
    view.setUint32(0x28, directorySectors, Endian.little); // directory sectors
    view.setUint32(0x30, 2, Endian.little); // first directory sector
    view.setUint32(0x38, miniStreamCutoff, Endian.little);
    view.setUint32(0x3C, 1, Endian.little); // first miniFAT sector
    view.setUint32(0x40, 1, Endian.little); // miniFAT sector count
    view.setUint32(0x44, endOfChain, Endian.little); // first DIFAT
    view.setUint32(0x48, 0, Endian.little); // DIFAT sector count
    view.setUint32(0x4C, 0, Endian.little); // DIFAT[0] → FAT sector 0
    for (var i = 1; i < 109; i++) {
      view.setUint32(0x4C + i * 4, freeSector, Endian.little);
    }
    return header;
  }

  // ── עזרים ────────────────────────────────────────────────────────────────

  static Uint8List _fatSectorBytes(List<int> table) {
    final bytes = Uint8List(sectorSize);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < table.length; i++) {
      view.setUint32(i * 4, table[i], Endian.little);
    }
    return bytes;
  }

  /// ריפוד לאורך מדויק. חריגה זורקת ולא נחתכת: קיצוץ שקט מוחק רשומות
  /// ומשאיר בדיקה שרצה על קובץ שאין בו את מה שהיא אמורה לכסות.
  static Uint8List _padTo(Uint8List data, int length) {
    if (data.length == length) return data;
    if (data.length > length) {
      throw StateError('הבלוק (${data.length} בתים) חורג מ-$length');
    }
    return Uint8List(length)..setRange(0, data.length, data);
  }

  static Uint8List _concat(List<Uint8List> parts) {
    final out = BytesBuilder();
    for (final part in parts) {
      out.add(part);
    }
    return out.takeBytes();
  }
}

/// סוגי רשומת ספרייה לפי המפרט.
abstract final class _EntryType {
  static const int storage = 1;
  static const int stream = 2;
  static const int root = 5;
}

class _Entry {
  final String key;
  final String name;
  final Uint8List data;
  final bool inner;

  const _Entry(this.key, this.name, this.data, {this.inner = false});
}

class _Layout {
  final List<Uint8List> contentSectors;
  final List<int> fat;
  final List<int> miniFat;
  final int miniStreamStart;
  final int miniStreamLength;
  final int Function(String key) startSectorOf;

  const _Layout({
    required this.contentSectors,
    required this.fat,
    required this.miniFat,
    required this.miniStreamStart,
    required this.miniStreamLength,
    required this.startSectorOf,
  });
}
