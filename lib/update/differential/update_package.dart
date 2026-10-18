import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:otzaria/utils/file/native_sha256.dart';

import 'managed_paths.dart';
import 'tree_fs.dart';

/// גרסת הסכמה של חבילת Windows. חבילה בגרסה שאינה מוכרת נדחית — היא
/// עלולה לתאר פעולות שאינן מוכרות כאן.
const int kUpdatePackageSchemaVersion = 1;

/// גרסת הסכמה של חבילת עץ (macOS, Linux): symlinks, הרשאות והעץ החדש המלא.
const int kUpdatePackageTreeSchemaVersion = 2;

/// שם קובץ המניפסט בתוך ה-ZIP של החבילה.
const String kUpdatePackageManifestEntryName = 'update-manifest.json';

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _unsafeTagCharacters = RegExp(r'[^A-Za-z0-9._-]');

/// שתי החבילות שמתפרסמות לכל מעבר גרסה: ה-patch, שנוסה תחילה, וחבילת
/// הקבצים המלאים שמשלימה ממנה כל ערך שאי אפשר להחיל.
enum UpdatePackageKind { patch, full }

/// תג שחרור כשם קובץ בטוח. חייב להישאר זהה ל-`sanitizeReleaseTag` של
/// `tool/release/generate_update_package.dart` — שם הנכס נבנה בשני הצדדים.
String sanitizeReleaseTagForAsset(String tag) =>
    tag.trim().replaceAll(_unsafeTagCharacters, '_');

/// שם נכס חבילת העדכון, בדיוק כפי שהבונה מפרסם אותו.
String updatePackageAssetNameFor({
  required String platform,
  required String architecture,
  required String fromReleaseTag,
  required String toReleaseTag,
  UpdatePackageKind kind = UpdatePackageKind.patch,
}) =>
    'otzaria-update-$platform-$architecture-'
    '${sanitizeReleaseTagForAsset(fromReleaseTag)}-to-'
    '${sanitizeReleaseTagForAsset(toReleaseTag)}'
    '${kind == UpdatePackageKind.full ? '-files' : ''}.zip';

/// הסיבה שבגללה אי אפשר להחיל את העדכון הדיפרנציאלי.
/// בכל אחת מהן הקורא חוזר למתקין המלא — לעולם לא ממשיך חלקית.
enum UpdateAbortReason {
  /// החבילה אינה קריאה, אינה תקפה, או בסכמה שאינה מוכרת.
  packageInvalid,

  /// ה-payload בחבילה אינו תואם את ה-hash שנרשם עבורו.
  packageCorrupt,

  /// החבילה מיועדת לפלטפורמה או לארכיטקטורה אחרת.
  targetMismatch,

  /// החבילה נבנתה מבסיס שאינו הגרסה המותקנת.
  baseVersionMismatch,

  /// הקובץ המקומי אינו תואם לא את הבסיס של ה-patch ולא את התוצאה,
  /// ולערך הזה אין קובץ מלא בחבילה.
  localFileUnusable,

  /// ערך נדחה לחבילת הקבצים המלאים, אך היא אינה זמינה או שאינה מכילה אותו.
  fallbackUnavailable,

  /// קובץ שנבנה ב-staging אינו תואם את ה-hash שבמניפסט.
  stagingVerificationFailed,

  /// כשל סביבה: zstd חסר, אין הרשאת כתיבה, דיסק מלא.
  environment,
}

/// העדכון הדיפרנציאלי אינו אפשרי. תמיד נזרק לפני שנגעו בהתקנה החיה.
class DifferentialUpdateUnavailable implements Exception {
  DifferentialUpdateUnavailable(this.reason, this.message);

  final UpdateAbortReason reason;
  final String message;

  @override
  String toString() =>
      'DifferentialUpdateUnavailable(${reason.name}): $message';
}

Never _fail(UpdateAbortReason reason, String message) =>
    throw DifferentialUpdateUnavailable(reason, message);

Never _invalid(String message) =>
    _fail(UpdateAbortReason.packageInvalid, message);

/// ערך בחבילה: קובץ שיש לכתוב, כ-patch על הקובץ הישן או כקובץ דחוס מלא.
class UpdatePackageEntry {
  UpdatePackageEntry({
    required this.path,
    required this.method,
    required this.compression,
    required this.entryName,
    required this.entrySize,
    required this.entrySha256,
    required this.newSize,
    required this.newSha256,
    this.oldSize,
    this.oldSha256,
  });

  final String path;
  final String method;
  final String compression;
  final String entryName;
  final int entrySize;
  final String entrySha256;
  final int newSize;
  final String newSha256;
  final int? oldSize;
  final String? oldSha256;

  bool get isPatch => method == 'patch';
}

/// קובץ אפליקציה שהוסר. אין קונסטרקטור ציבורי: מופע נוצר רק מרשימת
/// ה-`removals` של החבילה, שאינה יכולה להכיל נתוני משתמש.
class ManagedRemoval {
  ManagedRemoval._(this.path, this.oldSha256, this.oldSize);

  final String path;
  final String oldSha256;
  final int? oldSize;
}

/// מניפסט חבילת העדכון, אחרי אימות מלא.
class UpdatePackageManifest {
  UpdatePackageManifest._({
    required this.platform,
    required this.architecture,
    required this.fromReleaseTag,
    required this.fromReleaseVersion,
    required this.toReleaseTag,
    required this.toReleaseVersion,
    required this.entries,
    required this.removals,
    required this.payloadSize,
    required this.kind,
    required this.fallbackAssetName,
    this.newTree,
    this.links = const {},
    this.linkRemovals = const [],
  });

  /// העץ החדש המלא — רק בחבילת עץ. מולו מאומת העותק כולו.
  final TreeManifest? newTree;

  /// symlinks ליצירה או לשינוי יעד, בחבילת עץ.
  final Map<String, String> links;

  /// symlinks שאינם בגרסה החדשה, בחבילת עץ.
  final List<String> linkRemovals;

  bool get isTree => newTree != null;

  /// האם זו חבילת ה-patch או חבילת הקבצים המלאים.
  final UpdatePackageKind kind;

  /// שם נכס חבילת הקבצים המלאים, על חבילת ה-patch בלבד.
  final String? fallbackAssetName;

  final String platform;
  final String architecture;
  final String fromReleaseTag;
  final String fromReleaseVersion;
  final String toReleaseTag;
  final String toReleaseVersion;
  final List<UpdatePackageEntry> entries;
  final List<ManagedRemoval> removals;
  final int payloadSize;

  /// קורא ומאמת את המניפסט. החבילה מגיעה מהרשת, ולכן היא נבדקת כאן מחדש
  /// ולא נסמכת על האימות שנעשה בצד הבונה.
  factory UpdatePackageManifest.fromJson(Object? decoded) {
    if (decoded is! Map) _invalid('the update manifest is not a JSON object');
    final manifest = decoded;

    String requireString(String key) {
      final value = manifest[key];
      if (value is! String || value.trim().isEmpty) {
        _invalid('$key must be a non-empty string');
      }
      return value;
    }

    final schema = manifest['schemaVersion'];
    final tree = schema == kUpdatePackageTreeSchemaVersion;
    if (schema != kUpdatePackageSchemaVersion && !tree) {
      _invalid('unsupported schemaVersion $schema');
    }
    if (tree == (manifest['platform'] == 'windows')) {
      _invalid('schemaVersion $schema does not match the platform');
    }
    final fromTag = requireString('fromReleaseTag');
    final toTag = requireString('toReleaseTag');
    if (fromTag == toTag) _invalid('fromReleaseTag and toReleaseTag are equal');

    final rawVariant = manifest['variant'];
    final kind = switch (rawVariant) {
      'patch' => UpdatePackageKind.patch,
      'full' => UpdatePackageKind.full,
      _ => _invalid('variant must be patch or full'),
    };
    final fallbackAssetName = manifest['fallbackAssetName'];
    if (kind == UpdatePackageKind.full && fallbackAssetName != null) {
      _invalid('a full package has no fallback of its own');
    }
    if (fallbackAssetName != null &&
        (fallbackAssetName is! String || !fallbackAssetName.endsWith('.zip'))) {
      _invalid('fallbackAssetName must be a .zip asset name');
    }

    final rawEntries = manifest['entries'];
    final rawRemovals = manifest['removals'];
    if (rawEntries is! List) _invalid('entries must be a list');
    if (rawRemovals is! List) _invalid('removals must be a list');

    final paths = <String>{};
    final entryNames = <String>{};
    final entries = <UpdatePackageEntry>[];
    var payload = 0;

    for (final raw in rawEntries) {
      if (raw is! Map) _invalid('an entry is not a JSON object');
      final path = raw['path'];
      if (path is! String) _invalid('an entry has no path');
      final pathError = managedApplicationPathError(path);
      if (pathError != null) _invalid('entry $path: $pathError');
      if (!paths.add(path)) _invalid('entry $path: duplicate path');

      final entryName = raw['entry'];
      if (entryName is! String ||
          !entryName.startsWith('files/') ||
          managedPathError(entryName) != null) {
        _invalid('entry $path: the payload name must be files/<name>');
      }
      if (!entryNames.add(entryName)) {
        _invalid('entry $path: duplicate payload name');
      }

      final entrySize = raw['entrySize'];
      if (entrySize is! int || entrySize < 0) {
        _invalid('entry $path: entrySize must be a non-negative integer');
      }
      payload += entrySize;

      final newSize = raw['newSize'];
      if (newSize is! int || newSize < 0) {
        _invalid('entry $path: newSize must be a non-negative integer');
      }
      final entrySha = raw['entrySha256'];
      final newSha = raw['newSha256'];
      if (entrySha is! String || !_sha256Pattern.hasMatch(entrySha)) {
        _invalid('entry $path: entrySha256 must be 64 hex characters');
      }
      if (newSha is! String || !_sha256Pattern.hasMatch(newSha)) {
        _invalid('entry $path: newSha256 must be 64 hex characters');
      }

      final method = raw['method'];
      final compression = raw['compression'];
      final oldSha = raw['oldSha256'];
      final oldSize = raw['oldSize'];
      if (kind == UpdatePackageKind.full && method != 'full') {
        _invalid('entry $path: a full package carries full files only');
      }
      if (method == 'patch') {
        if (oldSha is! String || !_sha256Pattern.hasMatch(oldSha)) {
          _invalid('entry $path: a patch must record oldSha256');
        }
        if (oldSize is! int) _invalid('entry $path: a patch records oldSize');
        if (compression != 'zstd-patch-from') {
          _invalid('entry $path: a patch must use zstd-patch-from');
        }
      } else if (method == 'full') {
        if (oldSha != null) _invalid('entry $path: a full file has no base');
        if (compression != 'zstd') {
          _invalid('entry $path: a full file must use zstd');
        }
      } else {
        _invalid('entry $path: method must be patch or full');
      }

      entries.add(
        UpdatePackageEntry(
          path: path,
          method: method as String,
          compression: compression as String,
          entryName: entryName,
          entrySize: entrySize,
          entrySha256: entrySha,
          newSize: newSize,
          newSha256: newSha,
          oldSize: oldSize is int ? oldSize : null,
          oldSha256: oldSha is String ? oldSha : null,
        ),
      );
    }

    final removals = <ManagedRemoval>[];
    for (final raw in rawRemovals) {
      if (raw is! Map) _invalid('a removal is not a JSON object');
      final path = raw['path'];
      if (path is! String) _invalid('a removal has no path');
      final pathError = managedApplicationPathError(path);
      if (pathError != null) _invalid('removal $path: $pathError');
      if (paths.contains(path)) {
        _invalid('removal $path: the path is also written');
      }
      final oldSha = raw['oldSha256'];
      if (oldSha is! String || !_sha256Pattern.hasMatch(oldSha)) {
        _invalid('removal $path: oldSha256 must be 64 hex characters');
      }
      final oldSize = raw['oldSize'];
      removals.add(
        ManagedRemoval._(path, oldSha, oldSize is int ? oldSize : null),
      );
    }

    final payloadSize = manifest['payloadSize'];
    if (payloadSize is! int || payloadSize != payload) {
      _invalid('payloadSize must equal the sum of the entry sizes');
    }

    final treePart = tree ? _parseTree(manifest, entries, removals) : null;

    return UpdatePackageManifest._(
      platform: requireString('platform'),
      architecture: requireString('architecture'),
      fromReleaseTag: fromTag,
      fromReleaseVersion: requireString('fromReleaseVersion'),
      toReleaseTag: toTag,
      toReleaseVersion: requireString('toReleaseVersion'),
      entries: List.unmodifiable(entries),
      removals: List.unmodifiable(removals),
      payloadSize: payload,
      kind: kind,
      fallbackAssetName: fallbackAssetName as String?,
      newTree: treePart?.$1,
      links: treePart?.$2 ?? const {},
      linkRemovals: treePart?.$3 ?? const [],
    );
  }

  static (TreeManifest, Map<String, String>, List<String>) _parseTree(
    Map manifest,
    List<UpdatePackageEntry> entries,
    List<ManagedRemoval> removals,
  ) {
    final rawTree = manifest['newTree'];
    if (rawTree is! Map ||
        rawTree['files'] is! List ||
        rawTree['links'] is! List) {
      _invalid('newTree must hold files and links lists');
    }
    final files = <String, TreeFile>{};
    for (final raw in rawTree['files'] as List) {
      if (raw is! Map || raw['path'] is! String) {
        _invalid('newTree: a file has no path');
      }
      final path = raw['path'] as String;
      final error = managedApplicationPathError(path);
      if (error != null) _invalid('newTree $path: $error');
      final size = raw['size'];
      final sha = raw['sha256'];
      final mode = raw['mode'];
      if (size is! int ||
          size < 0 ||
          sha is! String ||
          !_sha256Pattern.hasMatch(sha) ||
          mode is! int ||
          mode < 0 ||
          mode > 0x1FF) {
        _invalid('newTree $path: needs size, sha256 and mode');
      }
      if (files.containsKey(path)) _invalid('newTree $path: duplicate path');
      files[path] = TreeFile(size: size, sha256: sha, mode: mode);
    }

    Map<String, String> parseLinks(Object? raw, String what) {
      if (raw is! List) _invalid('$what must be a list');
      final links = <String, String>{};
      for (final link in raw) {
        if (link is! Map ||
            link['path'] is! String ||
            link['target'] is! String) {
          _invalid('$what: a link needs path and target');
        }
        final path = link['path'] as String;
        final target = link['target'] as String;
        final error =
            managedApplicationPathError(path) ?? linkTargetError(path, target);
        if (error != null) _invalid('$what $path: $error');
        if (links.containsKey(path) || files.containsKey(path)) {
          _invalid('$what $path: duplicate path');
        }
        links[path] = target;
      }
      return links;
    }

    final treeLinks = parseLinks(rawTree['links'], 'newTree links');
    final through = pathsThroughLinksErrors([
      ...files.keys,
      ...treeLinks.keys,
    ], treeLinks.keys.toSet());
    if (through.isNotEmpty) _invalid('newTree: ${through.first}');

    for (final entry in entries) {
      final file = files[entry.path];
      if (file == null ||
          file.sha256 != entry.newSha256 ||
          file.size != entry.newSize) {
        _invalid('entry ${entry.path}: does not match newTree');
      }
    }
    for (final removal in removals) {
      if (files.containsKey(removal.path)) {
        _invalid('removal ${removal.path}: the path is in newTree');
      }
    }

    final links = <String, String>{};
    final rawLinks = manifest['links'];
    if (rawLinks is! List) _invalid('links must be a list');
    for (final link in rawLinks) {
      if (link is! Map || link['path'] is! String) {
        _invalid('links: a link has no path');
      }
      final path = link['path'] as String;
      if (treeLinks[path] == null || treeLinks[path] != link['target']) {
        _invalid('link $path: does not match newTree');
      }
      links[path] = treeLinks[path]!;
    }

    final linkRemovals = <String>[];
    final rawRemovals = manifest['linkRemovals'];
    if (rawRemovals is! List) _invalid('linkRemovals must be a list');
    for (final removal in rawRemovals) {
      if (removal is! Map || removal['path'] is! String) {
        _invalid('linkRemovals: an entry has no path');
      }
      final path = removal['path'] as String;
      final error = managedApplicationPathError(path);
      if (error != null) _invalid('link removal $path: $error');
      if (treeLinks.containsKey(path)) {
        _invalid('link removal $path: the link is in newTree');
      }
      linkRemovals.add(path);
    }

    return (
      TreeManifest(
        files: Map.unmodifiable(files),
        links: Map.unmodifiable(treeLinks),
      ),
      Map.unmodifiable(links),
      List.unmodifiable(linkRemovals),
    );
  }
}

/// חבילת עדכון פתוחה: המניפסט המאומת וגישה ל-payloads שבתוכה.
/// ה-ZIP נקרא בזרימה מהדיסק ב-isolate, כך שחבילה של מאות MB אינה נטענת לזיכרון.
class UpdatePackage {
  UpdatePackage._(this._path, this.manifest);

  final String _path;
  final UpdatePackageManifest manifest;

  /// פותח חבילה מקובץ ZIP ומאמת את המניפסט שבתוכה.
  static Future<UpdatePackage> open(File file) async {
    final path = file.path;
    final decoded = await Isolate.run(() => _readManifestJson(path));
    return UpdatePackage._(path, UpdatePackageManifest.fromJson(decoded));
  }

  /// כותב את ה-payload של הערך ל-[output] ומאמת את ה-hash שלו.
  Future<void> writePayloadTo(UpdatePackageEntry entry, File output) {
    final package = _path;
    final entryName = entry.entryName;
    final entrySha256 = entry.entrySha256;
    final path = entry.path;
    final outputPath = output.path;
    return Isolate.run(
      () => _extractVerifiedPayload(
        package,
        entryName,
        entrySha256,
        path,
        outputPath,
      ),
    );
  }
}

Object? _readManifestJson(String packagePath) {
  InputFileStream? input;
  try {
    final Archive archive;
    try {
      input = InputFileStream(packagePath);
      archive = ZipDecoder().decodeStream(input);
    } catch (error) {
      _invalid('the update package could not be read: $error');
    }
    final entry = archive.findFile(kUpdatePackageManifestEntryName);
    if (entry == null) {
      _invalid('the package has no $kUpdatePackageManifestEntryName');
    }
    try {
      return jsonDecode(utf8.decode(entry.readBytes()!));
    } catch (error) {
      _invalid('$kUpdatePackageManifestEntryName is not valid JSON: $error');
    }
  } finally {
    input?.closeSync();
  }
}

Future<void> _extractVerifiedPayload(
  String packagePath,
  String entryName,
  String entrySha256,
  String path,
  String outputPath,
) async {
  final input = InputFileStream(packagePath);
  try {
    final file = ZipDecoder().decodeStream(input).findFile(entryName);
    if (file == null || !file.isFile) {
      _fail(
        UpdateAbortReason.packageCorrupt,
        '$path: $entryName is missing from the package',
      );
    }
    final output = OutputFileStream(outputPath);
    try {
      file.writeContent(output);
    } finally {
      output.closeSync();
    }
  } finally {
    input.closeSync();
  }
  if (await sha256OfFileFast(outputPath) != entrySha256) {
    _fail(
      UpdateAbortReason.packageCorrupt,
      '$path: the package payload is corrupt',
    );
  }
}
