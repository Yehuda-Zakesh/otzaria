import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/personal_data_missing_warning.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/dialogs/backup_restore_flow.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory databases;
  late Directory backups;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('personal_data_missing_');
    databases = Directory(p.join(root.path, 'databases'))..createSync();
    backups = Directory(p.join(root.path, 'backups'))..createSync();
    Hive.init(root.path);
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      databases.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      backups.path,
    );
    AppPaths.debugOverrideDataRootPath(root.path);
    UserStateDatabase.instance.overridePath(
      p.join(databases.path, 'user_state.db'),
    );
    PersonalDataMissingWarning.debugReset();
  });

  tearDown(() async {
    BackupRestoreFlow.debugRestoreOverride = null;
    UserStateDatabase.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Hive.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  String writeBackup(
    DateTime at, {
    required bool withData,
    dynamic plugins,
  }) {
    final stamp = at.toIso8601String().replaceAll(':', '-');
    final file = File(p.join(backups.path, 'otzaria_backup_$stamp.json'));
    file.writeAsStringSync(
      jsonEncode({
        'version': '2.0',
        'bookmarks': [
          if (withData) {'ref': 'x'},
        ],
        'history': [],
        'notes': [],
        'plugins': plugins,
      }),
    );
    return file.path;
  }

  void wipeDatabases() {
    UserStateDatabase.instance.close();
    for (final f in databases.listSync()) {
      f.deleteSync();
    }
  }

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
  );

  /// עלייה מדומה: פתיחת user_state.db, זיהוי, והצגה אחרי החשיפה.
  Future<bool> startup(WidgetTester tester) async {
    await tester.runAsync(() async {
      UserStateDatabase.instance.close();
      await UserStateDatabase.instance.database;
      await PersonalDataMissingWarning.detect();
      // הבדיקה בגיבוי מפענחת ב-isolate, ולכן רצה בזמן אמיתי.
      unawaited(PersonalDataMissingWarning.showIfNeeded());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    return find.text(PersonalDataMissingWarning.title).evaluate().isNotEmpty;
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tap(find.text('לא עכשיו'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'מסדים אישיים שנמחקו מבחוץ — מוצגת הצעה לשחזר, ובהתקנה חדשה או בעדכון לא (issue #2610)',
    (tester) async {
      await pumpApp(tester);
      writeBackup(DateTime(2026, 10, 1), withData: true);

      // התקנה חדשה: עוד לא נטענה כאן ספרייה.
      expect(await startup(tester), isFalse);

      // ספרייה נטענה, ואחר כך המסדים נמחקו כשהתוכנה הייתה סגורה.
      File(p.join(root.path, 'library_loaded.marker')).createSync();
      wipeDatabases();
      expect(await startup(tester), isTrue);
      await dismiss(tester);
      expect(find.text(PersonalDataMissingWarning.title), findsNothing);

      // העלייה הקודמת יצרה את המסד מחדש, ולכן אין הודעה נוספת.
      expect(await startup(tester), isFalse);

      // עדכון מגרסה שלפני user_state.db: מסד אישי אחר קיים.
      wipeDatabases();
      File(p.join(databases.path, 'plugins_host.db')).createSync();
      expect(await startup(tester), isFalse);
    },
  );

  testWidgets('אין גיבוי שיש בו נתונים — אין הודעה (issue #2610)', (
    tester,
  ) async {
    await pumpApp(tester);
    File(p.join(root.path, 'library_loaded.marker')).createSync();

    // אין גיבוי כלל.
    expect(await startup(tester), isFalse);

    // יש גיבוי, אבל ריק.
    wipeDatabases();
    writeBackup(DateTime(2026, 10, 1), withData: false);
    expect(await startup(tester), isFalse);
  });

  testWidgets('גיבוי עם KV של תוסף בלבד מציע שחזור אחרי החשיפה', (
    tester,
  ) async {
    await pumpApp(tester);
    File(p.join(root.path, 'library_loaded.marker')).createSync();
    writeBackup(
      DateTime(2026, 10, 1),
      withData: false,
      plugins: [
        {
          'kvStore': [
            {'namespace': 'notes', 'key': 'entry', 'value_json': '"תוכן אישי"'},
          ],
        },
      ],
    );
    await tester.runAsync(() async {
      await UserStateDatabase.instance.database;
      await PersonalDataMissingWarning.detect();
    });
    expect(find.text(PersonalDataMissingWarning.title), findsNothing);
    await tester.runAsync(() async {
      unawaited(PersonalDataMissingWarning.showIfNeeded());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text(PersonalDataMissingWarning.title), findsOneWidget);
    await dismiss(tester);
  });

  for (final plugins in [
    [
      {
        'installation': {'plugin_id': 'builtin.empty'},
        'files': {'index.html': 'asset'},
        'permissions': [
          {'granted': 1},
        ],
      },
    ],
    {'invalid': 'old or corrupt plugin section'},
    [
      {'kvStore': 'invalid'},
    ],
  ]) {
    testWidgets('התקנה בלבד או סעיף תוספים פגום אינם מציעים שחזור: $plugins', (
      tester,
    ) async {
      await pumpApp(tester);
      File(p.join(root.path, 'library_loaded.marker')).createSync();
      writeBackup(DateTime(2026, 10, 1), withData: false, plugins: plugins);
      expect(await startup(tester), isFalse);
    });
  }

  testWidgets(
    '"שחזר מהגיבוי האחרון" מאשר ומשחזר מהגיבוי החדש ביותר (issue #2610)',
    (tester) async {
      await pumpApp(tester);
      File(p.join(root.path, 'library_loaded.marker')).createSync();
      writeBackup(DateTime(2026, 9, 1), withData: true);
      final latest = writeBackup(DateTime(2026, 10, 1), withData: true);
      final restored = <String>[];
      BackupRestoreFlow.debugRestoreOverride = (_, path) async =>
          restored.add(path);

      expect(await startup(tester), isTrue);
      await tester.tap(find.text(PersonalDataMissingWarning.restoreText));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      // אישור לפני שהנתונים הקיימים מוחלפים.
      expect(restored, isEmpty);
      await tester.tap(find.text('שחזר'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      expect(restored, [latest]);
    },
  );
}
