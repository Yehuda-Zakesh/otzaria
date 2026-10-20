import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_path_safety.dart';
import 'package:path/path.dart' as p;

/// קובץ שהורד למטמון ([PluginRemoteFileCache.fetch]).
typedef PluginRemoteFile = ({String path, String name, int size});

/// מטמון זמני, פרטי לכל תוסף, לקבצים ש-`network.fetchFile` הוריד.
///
/// הקובץ נשמר בתיקיית הטמפ' של המערכת ולא בתיקיית המשתמש, והתוסף מקבל אותו רק
/// כ-token של שרת הקבצים — לעולם לא נתיב. כל הורדה יושבת בתיקייה משלה
/// (`<תוסף>/<מזהה>/<שם>`), כך שהשם נשמר גם כששני קבצים נקראים אותו דבר.
class PluginRemoteFileCache {
  PluginRemoteFileCache({
    Directory? root,
    this.quotaBytes = defaultQuotaBytes,
    this.maxFiles = defaultMaxFiles,
    this.staleAfter = defaultStaleAfter,
    this.emptyDirGrace = defaultEmptyDirGrace,
  }) : root =
           root ??
           Directory(p.join(Directory.systemTemp.path, _defaultDirName));

  static final PluginRemoteFileCache instance = PluginRemoteFileCache();

  static const String _defaultDirName = 'otzaria_plugin_remote_files';

  /// המכסה הכוללת לתוסף. מעליה נמחקים הקבצים הוותיקים ביותר שלו.
  static const int defaultQuotaBytes = 256 * 1024 * 1024;
  static const int defaultMaxFiles = 128;

  /// תקרת קובץ בודד כשהתוסף לא ביקש אחרת, ותקרה שאי אפשר לעבור.
  static const int defaultMaxBytes = 50 * 1024 * 1024;
  static const int maxBytesLimit = 100 * 1024 * 1024;

  /// מספר ההורדות המקבילות המרבי לתוסף. המכסה נאכפת רק אחרי שהורדה מסתיימת,
  /// ולכן בלי תקרה כאן תוסף יכול להחזיק במקביל כמה פעמים את [maxBytesLimit].
  static const int maxConcurrentFetchesPerPlugin = 3;

  static const Duration defaultTimeout = Duration(minutes: 2);
  static const Duration maxTimeout = Duration(minutes: 10);

  /// קובץ שוותק מזה נמחק בהורדה הראשונה בהפעלה: הניקוי נעשה בעצלתיים, לא
  /// בעליית האפליקציה. הסף נדיב כי חלון משני רץ כתהליך נפרד על אותה תיקייה.
  static const Duration defaultStaleAfter = Duration(hours: 24);

  /// תיקיית הורדה ריקה צעירה מזה עשויה להיות הורדה שזה עתה נוצרה (אולי בתהליך
  /// אחר), ולכן הניקוי אינו נוגע בה.
  static const Duration defaultEmptyDirGrace = Duration(minutes: 5);

  final Directory root;
  final int quotaBytes;
  final int maxFiles;
  final Duration staleAfter;
  final Duration emptyDirGrace;
  bool _sweptStale = false;
  final Random _random = Random.secure();

  final Map<String, Set<Completer<void>>> _activeFetches = {};
  final Map<String, int> _revocations = {};

  /// מזהה מחזור החיים; תוצאה שהחלה לפני ביטול אינה מקבלת grant חדש.
  int generationForPlugin(String pluginId) => _revocations[pluginId] ?? 0;

  String? _canonicalRoot;

  /// תיקיית התוסף. מזהה ריק או של נקודות בלבד (`..`) היה מצביע על השורש או
  /// מחוצה לו, ו-[deleteForPlugin] מוחק אותה רקורסיבית.
  Directory _pluginDir(String pluginId) {
    final name = pluginId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final unsafe = RegExp(r'^\.*$').hasMatch(name);
    return Directory(
      p.join(root.path, unsafe ? '_${name.replaceAll('.', '_')}' : name),
    );
  }

  /// האם [path] הוא קובץ שהמטמון הוריד (`<root>/<תוסף>/<מזהה>/<שם>`).
  bool owns(String path) {
    final canonical = canonicalizeNearestExisting(path);
    return canonical != null && ownsCanonical(canonical);
  }

  /// בדיקה לקסיקלית לנתיב קנוני מול שורש המטמון; [pluginId] מגביל לתוסף מסוים.
  bool ownsCanonical(String canonicalPath, {String? pluginId}) {
    final base = _canonicalRoot ??= canonicalizeNearestExisting(root.path);
    return base != null &&
        p.equals(p.dirname(p.dirname(p.dirname(canonicalPath))), base) &&
        (pluginId == null ||
            p.equals(
              p.dirname(p.dirname(canonicalPath)),
              p.join(base, p.basename(_pluginDir(pluginId).path)),
            ));
  }

  /// מוריד את [uri] למטמון של [pluginId]. [timeout] חל על ההורדה כולה; אחרי
  /// שהמכסה חרגה נמחקים הקבצים הוותיקים של התוסף, מהישן לחדש. יותר מ-
  /// [maxConcurrentFetchesPerPlugin] הורדות במקביל נדחות ב-
  /// `error.too_many_requests`.
  Future<PluginRemoteFile> fetch(
    String pluginId,
    Uri uri, {
    required PluginFileDownloadService downloader,
    required Future<bool> Function(Uri) isAllowed,
    bool Function(Uri previous, Uri target)? isRedirectAllowed,
    int maxBytes = defaultMaxBytes,
    Duration timeout = defaultTimeout,
  }) async {
    final pluginDir = _pluginDir(pluginId);
    final key = pluginDir.path;
    if ((_activeFetches[key]?.length ?? 0) >= maxConcurrentFetchesPerPlugin) {
      throw Exception(
        'error.too_many_requests: too many concurrent file downloads',
      );
    }
    // נספר לפני ה-await הראשון, כדי שקריאות מקבילות לא יעקפו את התקרה.
    final abort = Completer<void>();
    (_activeFetches[key] ??= {}).add(abort);
    final generation = generationForPlugin(pluginId);
    final dir = Directory(p.join(pluginDir.path, _randomId()));
    var timedOut = false;
    Future<PluginRemoteFile> download() async {
      try {
        await _sweepStale();
        final saved = await downloader.downloadToDirectory(
          uri,
          dir,
          isAllowed: isAllowed,
          isRedirectAllowed: isRedirectAllowed,
          maxBytes: maxBytes,
          expired: () => abort.isCompleted,
          abortTrigger: abort.future,
        );
        final size = await File(saved.path).length();
        if (timedOut) throw TimeoutException(null);
        if (generation != generationForPlugin(pluginId)) {
          throw Exception('error.unavailable: remote file download revoked');
        }
        return (
          path: saved.path,
          name: saved.filename,
          size: size,
        );
      } catch (_) {
        await _deleteDir(dir);
        if (generation != generationForPlugin(pluginId)) {
          throw Exception('error.unavailable: remote file download revoked');
        }
        if (timedOut) throw TimeoutException('Remote file download timed out');
        rethrow;
      } finally {
        _activeFetches[key]?.remove(abort);
        if (_activeFetches[key]?.isEmpty ?? false) _activeFetches.remove(key);
      }
    }

    try {
      final pending = download().onError<Object>((error, stack) async {
        await _removeIfIdle(pluginDir);
        Error.throwWithStackTrace(error, stack);
      });
      // http אינו מבטל DNS/connect שכבר רץ; ה-RPC לא ממתין לו, וה-slot נשאר תפוס.
      final file = await pending.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException('Remote file download timed out');
        },
      );
      await _evictOldest(pluginDir, keep: dir);
      if (generation != generationForPlugin(pluginId)) {
        await _deleteDir(dir);
        throw Exception('error.unavailable: remote file download revoked');
      }
      return file;
    } catch (_) {
      await _removeIfIdle(pluginDir);
      rethrow;
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// מוחק את ההורדה ש-[path] שייך לה, אם הוא במטמון, ואת תיקיית התוסף אם
  /// התרוקנה. בטוח לקרוא על כל נתיב.
  Future<void> delete(String path) async {
    if (!owns(path)) return;
    final downloadDir = File(path).parent;
    await _deleteDir(downloadDir);
    await _removeIfIdle(downloadDir.parent);
  }

  /// מוחק את כל הקבצים של [pluginId] — בהסרה, בכיבוי או באיפוס של התוסף.
  Future<void> deleteForPlugin(String pluginId) async {
    _revocations[pluginId] = generationForPlugin(pluginId) + 1;
    for (final abort in _activeFetches[_pluginDir(pluginId).path] ?? {}) {
      if (!abort.isCompleted) abort.complete();
    }
    await _deleteDir(_pluginDir(pluginId));
  }

  String _randomId() => List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// מפנה את הוותיקים לפי בייטים ומספר קבצים; חלקיים פעילים אינם נמחקים.
  /// אם קבצים נעולים מונעים פינוי, ההורדה החדשה נדחית ונמחקת.
  Future<void> _evictOldest(
    Directory pluginDir, {
    required Directory keep,
  }) async {
    final entries = <({Directory dir, int size, DateTime modified})>[];
    var total = 0;
    var count = 0;
    var downloadingBytes = 0;
    var downloadingCount = 0;
    try {
      await for (final entry in pluginDir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        var size = 0;
        var downloading = false;
        var modified = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          await for (final file in entry.list(followLinks: false)) {
            if (file is! File) continue;
            final stat = await file.stat();
            size += stat.size;
            if (stat.modified.isAfter(modified)) modified = stat.modified;
            downloading |=
                p.basename(file.path) ==
                PluginFileDownloadService.partialFileName;
          }
        } on FileSystemException {
          continue; // הורדה שהסתיימה או נמחקה בזמן הסריקה.
        }
        total += size;
        count++;
        if (downloading) {
          downloadingBytes += size;
          downloadingCount++;
        }
        if (!downloading && !p.equals(entry.path, keep.path)) {
          entries.add((dir: entry, size: size, modified: modified));
        }
      }
    } on FileSystemException {
      return; // תיקייה שנמחקה במקביל (הסרת תוסף) — אין מה לפנות.
    }
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= quotaBytes && count <= maxFiles) break;
      // קובץ נעול (ווינדוס) נשאר, ולכן גודלו נשאר במכסה.
      if (await _deleteDir(entry.dir)) {
        total -= entry.size;
        count--;
      }
    }
    // הורדות פעילות מוגבלות בנפרד ומתפנות בסיום; קבצים נעולים אינם פטור מהמכסה.
    if (total - downloadingBytes > quotaBytes ||
        count - downloadingCount > maxFiles) {
      await _deleteDir(keep);
      throw Exception('error.too_many_requests: remote file cache is full');
    }
  }

  Future<void> _sweepStale() async {
    if (_sweptStale) return;
    _sweptStale = true;
    try {
      if (!await root.exists()) return;
      final now = DateTime.now();
      final cutoff = now.subtract(staleAfter);
      final emptyCutoff = now.subtract(emptyDirGrace);
      await for (final plugin in root.list(followLinks: false)) {
        if (plugin is! Directory) continue;
        await for (final entry in plugin.list(followLinks: false)) {
          if (entry is! Directory) continue;
          final modified = (await entry.stat()).modified;
          // גם תיקיית הורדה ריקה — שריד של מחיקה שנחסמה (קובץ פתוח בווינדוס).
          final empty = await entry.list(followLinks: false).isEmpty;
          if (modified.isBefore(cutoff) ||
              (empty && modified.isBefore(emptyCutoff))) {
            await _deleteDir(entry);
          }
        }
        await _removeIfIdle(plugin);
      }
    } catch (_) {
      // ניקוי best-effort; אין להפיל בגללו הורדה.
    }
  }

  /// מוחק את תיקיית התוסף הריקה שנשארה אחרי הורדה שנכשלה, אלא אם הורדה אחרת
  /// שלו רצה (היא הייתה מאבדת את התיקייה באמצע היצירה).
  Future<void> _removeIfIdle(Directory pluginDir) async {
    if (_activeFetches.containsKey(pluginDir.path)) return;
    try {
      if (await pluginDir.exists()) await pluginDir.delete(); // לא רקורסיבי
    } catch (_) {
      // לא ריקה — יש בה הורדות תקינות.
    }
  }

  /// מוחק תיקייה. מחזיר `false` אם היא נשארה (קובץ נעול).
  Future<bool> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return true;
    } catch (_) {
      // בווינדוס קובץ פתוח (למשל PDF שנטען ב-iframe) חוסם את מחיקת התיקייה, גם
      // כשהקובץ עצמו נמחק: מוחקים את התוכן בנפרד ומנסים שוב על התיקייה.
      try {
        await for (final entry in dir.list(followLinks: false)) {
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
        }
        await dir.delete();
      } catch (_) {
        // המכסה והסריקה הבאה (ריקות ישנות) יטפלו בשארית.
      }
      return !await dir.exists();
    }
  }
}
