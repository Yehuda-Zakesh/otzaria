import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

/// ANR אחד שהמערכת רשמה להפעלה קודמת.
@immutable
class AndroidAnr {
  const AndroidAnr({
    required this.timestamp,
    required this.description,
    required this.mainThreadTrace,
    required this.signature,
    required this.details,
  });

  final DateTime timestamp;
  final String? description;
  final String? mainThreadTrace;
  final CrashSignature signature;

  /// מידע אבחון פרטי, עד [AndroidAnrSource.maxDetailsLength] תווים.
  final String details;
}

/// מחזיר את תשובת `getAnrExits` לערוץ `otzaria/app_exit_info`.
typedef AnrExitsInvoker = Future<Object?> Function(int sinceMs);

/// קורא ANR-ים מההפעלות הקודמות (ApplicationExitInfo, אנדרואיד 11+) ומחזיר
/// כל אחד פעם אחת, לפי סימן-מים שנשמר בקובץ ליד errors.txt.
class AndroidAnrSource {
  AndroidAnrSource({
    AnrExitsInvoker? invoker,
    String? stateFilePath,
    bool? isAndroid,
    DateTime Function()? clock,
  }) : _invoker = invoker ?? _invokeChannel,
       _customStatePath = stateFilePath,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _clock = clock ?? DateTime.now;

  static const MethodChannel _channel = MethodChannel('otzaria/app_exit_info');
  static const String stateFileName = 'android_anr_state.json';
  static const int maxDetailsLength = 8000;

  /// IMPORTANCE_VISIBLE; מעליו (שירות, רקע) המשתמש לא חווה תקיעה.
  static const int maxReportedImportance = 200;

  /// בלי ערך מהמערכת — מדווחים, כדי לא לאבד ANR אמיתי.
  static bool isUserPerceived(int? importance) =>
      importance == null || importance <= maxReportedImportance;

  final AnrExitsInvoker _invoker;
  final String? _customStatePath;
  final bool _isAndroid;
  final DateTime Function() _clock;

  String get stateFilePath =>
      _customStatePath ??
      p.join(p.dirname(ErrorLogFile.resolvePath()), stateFileName);

  static Future<Object?> _invokeChannel(int sinceMs) =>
      _channel.invokeMethod<Object?>('getAnrExits', {'sinceMs': sinceMs});

  /// ה-ANR החדש ביותר שטרם דווח, או null. בהרצה הראשונה רק נרשם סימן-המים,
  /// והוא נשמר לפני ההחזרה כדי שקריסה בזמן הדיווח לא תחזיר אותו שוב.
  Future<AndroidAnr?> takeNewAnr() async {
    if (!_isAndroid) return null;
    try {
      final watermark = await _readWatermark();
      if (watermark == null) {
        final response = _asMap(
          await _invoker(_clock().millisecondsSinceEpoch),
        );
        final newest =
            _asInt(response?['newestAnyTimestamp']) ??
            _clock().millisecondsSinceEpoch;
        await _writeWatermark(newest);
        return null;
      }

      final response = _asMap(await _invoker(watermark));
      final exits = (response?['exits'] as List?) ?? const [];
      Map? newest;
      var newestTs = watermark;
      var seenTs = watermark;
      for (final exit in exits) {
        if (exit is! Map) continue;
        final ts = _asInt(exit['timestamp']);
        if (ts == null || ts <= watermark) continue;
        if (ts > seenTs) seenTs = ts;
        if (!isUserPerceived(_asInt(exit['importance'])) || ts <= newestTs) {
          continue;
        }
        newest = exit;
        newestTs = ts;
      }
      // ANR ברקע מסומן כנראה גם כשאינו מדווח, כדי שלא ייבדק שוב.
      if (seenTs > watermark) await _writeWatermark(seenTs);
      if (newest == null) return null;
      return _toAnr(newest, newestTs);
    } catch (error) {
      debugPrint('AndroidAnrSource: $error');
      return null;
    }
  }

  AndroidAnr _toAnr(Map exit, int timestampMs) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final description = exit['description'] as String?;
    final trace = exit['mainThreadTrace'] as String?;
    return AndroidAnr(
      timestamp: timestamp,
      description: description,
      mainThreadTrace: trace,
      signature: anrSignatureFromTrace(trace),
      details: anrDetails(
        timestamp: timestamp,
        description: description,
        importance: _asInt(exit['importance']),
        mainThreadTrace: trace,
      ),
    );
  }

  Future<int?> _readWatermark() async {
    final file = File(stateFilePath);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map ? _asInt(json['lastTimestamp']) : null;
    } on FormatException {
      return null;
    }
  }

  // כשל בכתיבה זורק: עדיף לא לדווח מאשר לדווח שוב בכל הפעלה.
  Future<void> _writeWatermark(int timestampMs) async {
    final file = File(stateFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'lastTimestamp': timestampMs}),
      flush: true,
    );
  }

  static Map? _asMap(Object? value) => value is Map ? value : null;

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;
}

/// טקסט הדיווח: תיאור המערכת ומחסנית ה-main, חתוך ל-[maxLength].
String anrDetails({
  required DateTime timestamp,
  String? description,
  int? importance,
  String? mainThreadTrace,
  int maxLength = AndroidAnrSource.maxDetailsLength,
}) {
  final header = StringBuffer()
    ..writeln('Android ANR (application not responding)')
    ..writeln('Time: ${timestamp.toUtc().toIso8601String()}');
  if (description != null && description.trim().isNotEmpty) {
    header.writeln('Description: ${description.trim()}');
  }
  if (importance != null) header.writeln('Importance: $importance');
  header.writeln('Main thread:');
  final trace = (mainThreadTrace == null || mainThreadTrace.trim().isEmpty)
      ? '(no trace)'
      : mainThreadTrace.trimRight();
  final text = '$header$trace';
  if (text.length <= maxLength) return text;
  const marker = '\n...(truncated)';
  return text.substring(0, maxLength - marker.length) + marker;
}

/// חתימה ל-ANR: הסוג תמיד `ANR`, ועד 3 פריימים מנורמלים ממחסנית ה-main.
CrashSignature anrSignatureFromTrace(String? mainThreadTrace) {
  final frames = <_AnrFrame>[];
  final lines = const LineSplitter().convert(mainThreadTrace ?? '');
  // בלי כותרת "main" — הטקסט כולו הוא כבר קטע ה-main.
  var inMain = !lines.any((l) => l.startsWith('"main"'));
  var sawContent = false;
  for (final line in lines) {
    if (!inMain) {
      inMain = line.startsWith('"main"');
      sawContent = inMain;
      continue;
    }
    if (line.trim().isEmpty) {
      if (sawContent) break;
      continue;
    }
    sawContent = true;
    final frame = _parseFrame(line);
    if (frame != null) frames.add(frame);
  }
  final preferred = frames.where((f) => f.isApp).toList();
  final meaningful = frames.where((f) => !f.isGeneric).toList();
  final chosen = preferred.isNotEmpty
      ? preferred
      : meaningful.isNotEmpty
      ? meaningful
      : frames;
  return CrashSignature(
    exceptionType: 'ANR',
    frames: [
      for (final f in chosen.take(CrashSignature.maxFrames))
        f.text.length <= CrashSignature.maxFrameLength
            ? f.text
            : f.text.substring(0, CrashSignature.maxFrameLength),
    ],
  );
}

class _AnrFrame {
  const _AnrFrame(this.text, {required this.isApp, required this.isGeneric});
  final String text;
  final bool isApp;
  final bool isGeneric;
}

final RegExp _javaFrame = RegExp(r'^\s*at\s+([\w$.<>-]+)\(');
final RegExp _nativeFrame = RegExp(
  r'^\s*native:\s+#\d+\s+pc\s+(?:0x)?([0-9a-fA-F]+)\s+(\S+)(.*)$',
);
final RegExp _parenGroup = RegExp(r'\(([^()]*(?:\([^()]*\)[^()]*)*)\)');

const List<String> _frameworkJavaPrefixes = [
  'android.',
  'androidx.',
  'com.android.',
  'com.google.android.',
  'java.',
  'javax.',
  'kotlin.',
  'kotlinx.',
  'dalvik.',
  'libcore.',
  'sun.',
];

const List<String> _genericJavaPrefixes = [
  'android.os.MessageQueue.nativePollOnce',
  'android.os.Looper.',
  'com.android.internal.os.',
  'java.lang.reflect.',
  'dalvik.',
];

const Set<String> _genericNativeLibs = {'libc.so'};

_AnrFrame? _parseFrame(String line) {
  final java = _javaFrame.firstMatch(line);
  if (java != null) {
    final name = java.group(1)!;
    return _AnrFrame(
      name,
      isApp: !_frameworkJavaPrefixes.any(name.startsWith),
      isGeneric: _genericJavaPrefixes.any(name.startsWith),
    );
  }
  final native = _nativeFrame.firstMatch(line);
  if (native == null) return null;
  final pc = native.group(1)!.replaceFirst(RegExp(r'^0+(?=.)'), '');
  final path = native.group(2)!;
  final lib = path.split(RegExp(r'[/!]')).last;
  String? symbol;
  for (final group in _parenGroup.allMatches(native.group(3)!)) {
    final inner = group.group(1)!.trim();
    if (inner.isEmpty ||
        inner.startsWith('BuildId:') ||
        inner.startsWith('offset ')) {
      continue;
    }
    // ההיסט בתוך הפונקציה משתנה בין גרסאות; שם הפונקציה יציב.
    symbol = inner.replaceFirst(RegExp(r'\+\d+$'), '');
    break;
  }
  return _AnrFrame(
    symbol != null ? '$lib $symbol' : '$lib+0x$pc',
    isApp: path.startsWith('/data/'),
    isGeneric: _genericNativeLibs.contains(lib),
  );
}
