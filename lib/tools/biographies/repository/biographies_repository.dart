import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/tools/biographies/data/biographies_codec.dart';
import 'package:otzaria/tools/biographies/models/biography.dart';

/// שכבת הנתונים של אזור הביוגרפיות.
///
/// הקובץ מגיע משני מקורות, לפי סדר עדיפות: העותק שמערכת העדכונים הורידה
/// לשורש תיקיית הנתונים, ואם אין — הקובץ הארוז באפליקציה עצמה (מוזרק
/// לחבילה בזמן בנייה, ולכן כלול בכל מתקין ועובד מיד גם ללא רשת).
class BiographiesRepository {
  /// כמו `DictionaryLookupRepository`: singleton שנצרך ישירות מהמסכים,
  /// עם constructor להזרקת מקורות חלופיים בבדיקות.
  static final BiographiesRepository instance = BiographiesRepository();

  static const String bundledAssetKey = 'assets/bio/biographies.tsb';

  final Future<String> Function() _updatedPathProvider;
  final Future<ByteData> Function(String key) _loadAsset;

  Future<List<Biography>>? _loading;

  BiographiesRepository({
    Future<String> Function()? updatedPathProvider,
    Future<ByteData> Function(String key)? loadAsset,
  }) : _updatedPathProvider =
           updatedPathProvider ?? AppPaths.getBiographiesPath,
       _loadAsset = loadAsset ?? rootBundle.load;

  /// טוען את כל הביוגרפיות, ממוינות לפי שם. הטעינה מתבצעת פעם אחת;
  /// קריאות חוזרות (גם מקבילות) מקבלות את אותו Future.
  ///
  /// זורק [StateError] כשאין קובץ בשום מקור.
  Future<List<Biography>> loadAll() => _loading ??= _load();

  Future<List<Biography>> _load() async {
    try {
      final bytes = await _readBytes();
      // הפענוח (XOR + gzip + JSON של ~2.3MB) רץ ב-isolate כדי לא לחסום את ה-UI.
      final entries = await compute(_decodeAndParse, bytes);
      entries.sort((a, b) => a.name.compareTo(b.name));
      return entries;
    } catch (_) {
      // כישלון לא ננעל: פתיחה הבאה תנסה שוב (למשל אחרי שהעדכון הוריד).
      _loading = null;
      rethrow;
    }
  }

  Future<Uint8List> _readBytes() async {
    final updated = File(await _updatedPathProvider());
    if (await updated.exists()) return updated.readAsBytes();
    try {
      final data = await _loadAsset(bundledAssetKey);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      throw StateError('נתוני הביוגרפיות אינם זמינים');
    }
  }

  /// מסננת וממיינת ערכים לפי שם או כינוי. מקור יחיד למסך הביוגרפיות
  /// ול-API של התוספים, כדי ששניהם יציגו את אותה תוצאה באותו סדר.
  static List<Biography> filter(List<Biography> entries, String query) {
    query = query.trim();
    if (query.isEmpty) return entries;

    // ביטוי "מילה שלמה" נבנה פעם אחת לכל קריאה — לא בכל השוואה בתוך
    // המיון — כדי לא לקמפל RegExp מחדש O(n log n) פעמים על אלפי הערכים.
    final wholeWordPattern = RegExp('(^|\\s)${RegExp.escape(query)}(\$|\\s)');

    final ranked = <_RankedBiography>[];
    for (final bio in entries) {
      if (bio.name.contains(query) ||
          bio.appelations.any((a) => a.contains(query))) {
        ranked.add(
          _RankedBiography(bio, _matchRank(bio.name, query, wholeWordPattern)),
        );
      }
    }

    ranked.sort((a, b) {
      final rankCompare = a.rank.compareTo(b.rank);
      if (rankCompare != 0) return rankCompare;
      return a.bio.name.compareTo(b.bio.name);
    });

    return ranked.map((r) => r.bio).toList();
  }

  /// דירוג התאמת שם לשאילתה: נמוך = דומה יותר.
  /// מדויק < מתחיל ב- < מילה שלמה < מכיל < רק בכינוי.
  static int _matchRank(String name, String query, RegExp wholeWordPattern) {
    if (name == query) return 0;
    if (name.startsWith(query)) return 1;
    if (wholeWordPattern.hasMatch(name)) return 2;
    if (name.contains(query)) return 3;
    return 4;
  }

  static List<Biography> _decodeAndParse(Uint8List bytes) {
    final payload = BiographiesCodec.decode(bytes);
    return ((payload['entries'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Biography.fromEntry)
        .toList();
  }
}

/// ביוגרפיה עם דירוג ההתאמה שלה, מחושב פעם אחת לפני המיון.
class _RankedBiography {
  final Biography bio;
  final int rank;

  const _RankedBiography(this.bio, this.rank);
}
