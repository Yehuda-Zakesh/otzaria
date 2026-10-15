import 'dart:io';
import 'dart:typed_data';

import 'sfnt_bytes.dart';

const Set<String> _metadataTags = {'cmap', 'OS/2', 'head', 'name', 'fvar'};
const Map<String, int> _minTableLength = {'OS/2': 96, 'head': 64};

class _TableReference {
  final int recordOffset;
  final int sourceOffset;

  const _TableReference(this.recordOffset, this.sourceOffset);
}

class _FaceDirectory {
  final int? ttcIndex;
  final Uint8List bytes;
  final List<_TableReference> tables;
  int outputOffset = 0;

  _FaceDirectory({
    required this.ttcIndex,
    required this.bytes,
    required this.tables,
  });
}

Uint8List? readMetadataSync(String path) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    final fileLength = raf.lengthSync();
    if (fileLength < 12) return null;

    final header = _readAt(raf, 0, 12);
    if (header == null) return null;

    Uint8List? ttcHeader;
    final bases = <({int offset, int? ttcIndex})>[];
    if (header.sfntTag(0) == 'ttcf') {
      final numFonts = header.sfntU32(8);
      if (numFonts <= 0 || numFonts > 0xFFFF) return null;
      final headerLength = 12 + numFonts * 4;
      ttcHeader = _readAt(raf, 0, headerLength);
      if (ttcHeader == null) return null;
      for (var i = 0; i < numFonts; i++) {
        final offset = ttcHeader.sfntU32(12 + i * 4);
        if (offset > 0 && offset < fileLength) {
          bases.add((offset: offset, ttcIndex: i));
        }
      }
    } else {
      bases.add((offset: 0, ttcIndex: null));
    }

    final faces = <_FaceDirectory>[];
    final tableEnds = <int, int>{};
    for (final base in bases) {
      final offsetTable = _readAt(raf, base.offset, 12);
      if (offsetTable == null) continue;
      final numTables = offsetTable.sfntU16(4);
      if (numTables <= 0) continue;
      final directoryLength = 12 + numTables * 16;
      final directory = _readAt(raf, base.offset, directoryLength);
      if (directory == null) continue;

      final tables = <_TableReference>[];
      for (var i = 0; i < numTables; i++) {
        final record = 12 + i * 16;
        final tag = directory.sfntTag(record);
        if (!_metadataTags.contains(tag)) continue;
        final sourceOffset = directory.sfntU32(record + 8);
        final declaredLength = directory.sfntU32(record + 12);
        final minimumLength = _minTableLength[tag] ?? 0;
        final length = declaredLength > minimumLength
            ? declaredLength
            : minimumLength;
        if (sourceOffset < 0 || length <= 0 || sourceOffset >= fileLength) {
          continue;
        }
        final end = sourceOffset + length > fileLength
            ? fileLength
            : sourceOffset + length;
        if (end <= sourceOffset) continue;
        final previousEnd = tableEnds[sourceOffset];
        if (previousEnd == null || end > previousEnd) {
          tableEnds[sourceOffset] = end;
        }
        tables.add(_TableReference(record, sourceOffset));
      }
      faces.add(
        _FaceDirectory(
          ttcIndex: base.ttcIndex,
          bytes: directory,
          tables: tables,
        ),
      );
    }
    if (faces.isEmpty) return null;

    final sourceOffsets = tableEnds.keys.toList()..sort();
    var outputLength =
        (ttcHeader?.length ?? 0) +
        faces.fold<int>(0, (sum, face) => sum + face.bytes.length);
    for (final sourceOffset in sourceOffsets) {
      outputLength += tableEnds[sourceOffset]! - sourceOffset;
    }

    final buffer = Uint8List(outputLength);
    var cursor = 0;
    if (ttcHeader != null) {
      buffer.setRange(0, ttcHeader.length, ttcHeader);
      cursor = ttcHeader.length;
    }
    for (final face in faces) {
      face.outputOffset = cursor;
      buffer.setRange(cursor, cursor + face.bytes.length, face.bytes);
      cursor += face.bytes.length;
      final ttcIndex = face.ttcIndex;
      if (ttcIndex != null) {
        _writeU32(buffer, 12 + ttcIndex * 4, face.outputOffset);
      }
    }

    final compactOffsets = <int, int>{};
    for (final sourceOffset in sourceOffsets) {
      compactOffsets[sourceOffset] = cursor;
      final end = tableEnds[sourceOffset]!;
      raf.setPositionSync(sourceOffset);
      raf.readIntoSync(buffer, cursor, cursor + end - sourceOffset);
      cursor += end - sourceOffset;
    }
    for (final face in faces) {
      for (final table in face.tables) {
        _writeU32(
          buffer,
          face.outputOffset + table.recordOffset + 8,
          compactOffsets[table.sourceOffset]!,
        );
      }
    }
    return buffer;
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

Uint8List? _readAt(RandomAccessFile raf, int offset, int length) {
  if (offset < 0 || length <= 0) return null;
  raf.setPositionSync(offset);
  final bytes = raf.readSync(length);
  return bytes.length == length ? bytes : null;
}

void _writeU32(Uint8List d, int o, int value) {
  d[o] = (value >> 24) & 0xFF;
  d[o + 1] = (value >> 16) & 0xFF;
  d[o + 2] = (value >> 8) & 0xFF;
  d[o + 3] = value & 0xFF;
}
