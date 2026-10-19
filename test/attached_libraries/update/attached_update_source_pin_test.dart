import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_source.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _keyA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _keyB = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const _urlA = 'https://example.org/lib/manifest.json';
const _urlB = 'https://evil.example.net/manifest.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late AttachedLibraryRegistry registry;
  var counter = 0;

  AttachedLibrariesRepository build() => AttachedLibrariesRepository(
    registry: registry,
    probe: (path) async => AttachedLibraryProbe.probeSync(path),
    copyDirectory: () async => p.join(tempDir.path, 'copies'),
    copyByDefault: false,
  );

  void setMeta(String path, Map<String, String?> meta) {
    final db = sqlite3.sqlite3.open(path);
    for (final entry in meta.entries) {
      db.execute('DELETE FROM schema_meta WHERE key = ?', [entry.key]);
      if (entry.value != null) {
        db.execute('INSERT INTO schema_meta VALUES (?, ?)', [
          entry.key,
          entry.value,
        ]);
      }
    }
    db.close();
    // טביעת האצבע משתנה גם כשהכתיבה נופלת באותה אלפית שנייה.
    File(path).setLastModifiedSync(
      DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  String fixture({String? url = _urlA, String? key = _keyA}) {
    final dir = Directory(p.join(tempDir.path, 'src${counter++}'))
      ..createSync(recursive: true);
    final created = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
    final path = p.join(dir.path, 'lib.db');
    File(created).renameSync(path);
    setMeta(path, {
      'library_id': 'my-lib',
      'update_manifest_url': url,
      'update_public_key': key,
    });
    return path;
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_update_pin');
    registry = AttachedLibraryRegistry(idleTimeout: null);
  });

  tearDown(() async {
    await registry.closeAll();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('הבדיקה קוראת את מקור העדכונים מ-schema_meta', () {
    final result = AttachedLibraryProbe.probeSync(fixture());
    expect(
      result.updateSource,
      const AttachedLibraryUpdateSource(
        libraryId: 'my-lib',
        manifestUrl: _urlA,
        publicKey: _keyA,
      ),
    );
  });

  test('כתובת http או מפתח פגום — אין מקור עדכונים', () {
    expect(
      AttachedLibraryProbe.probeSync(
        fixture(url: 'http://example.org/m.json'),
      ).updateSource,
      isNull,
    );
    expect(
      AttachedLibraryProbe.probeSync(fixture(key: 'AAAA')).updateSource,
      isNull,
    );
    expect(
      AttachedLibraryProbe.probeSync(fixture(key: null)).updateSource,
      isNull,
    );
  });

  test('המקור נעוץ בצירוף ונשמר ב-JSON', () async {
    final result = await build().importFile(fixture());
    final library = result.library!;
    expect(library.updateSource?.publicKey, _keyA);
    expect(library.updateSourceMismatch, isFalse);
    final restored = AttachedLibrary.fromJson(library.toJson());
    expect(restored.updateSource, library.updateSource);
    expect(restored.updateSourceProbed, isTrue);
  });

  test('מפתח או כתובת אחרים באותו slug — הנעוץ נשמר ומסומנת סטייה', () async {
    final path = fixture();
    final repository = build();
    await repository.importFile(path);

    setMeta(path, {'update_public_key': _keyB});
    await repository.rescan();
    var library = repository.libraries.single;
    expect(library.updateSource?.publicKey, _keyA);
    expect(library.updateSourceMismatch, isTrue);

    setMeta(path, {'update_public_key': _keyA, 'update_manifest_url': _urlB});
    await repository.rescan();
    library = repository.libraries.single;
    expect(library.updateSource?.manifestUrl, _urlA);
    expect(library.updateSourceMismatch, isTrue);

    setMeta(path, {'update_manifest_url': _urlA});
    await repository.rescan();
    expect(repository.libraries.single.updateSourceMismatch, isFalse);
  });

  test('הסרת המקור מהמסד — הנעוץ נשמר ומסומנת סטייה', () async {
    final path = fixture();
    final repository = build();
    await repository.importFile(path);
    setMeta(path, {'update_public_key': null});
    await repository.rescan();
    final library = repository.libraries.single;
    expect(library.updateSource?.publicKey, _keyA);
    expect(library.updateSourceMismatch, isTrue);
  });

  test('מסד שצורף לפני התכונה נבדק שוב פעם אחת ונעוץ (TOFU)', () async {
    final path = fixture();
    final repository = build();
    await repository.importFile(path);
    final legacy = repository.libraries.single.copyWith(
      clearUpdateSource: true,
      updateSourceProbed: false,
    );
    registry.update([legacy]);
    expect(repository.libraries.single.updateSource, isNull);

    await repository.rescan();
    final library = repository.libraries.single;
    expect(library.updateSource?.publicKey, _keyA);
    expect(library.updateSourceProbed, isTrue);
    expect(library.updateSourceMismatch, isFalse);
  });

  test('מסד בלי מקור עדכונים — לא נעוץ דבר', () async {
    final result = await build().importFile(fixture(url: null));
    expect(result.library!.updateSource, isNull);
    expect(result.library!.updateSourceMismatch, isFalse);
  });
}
