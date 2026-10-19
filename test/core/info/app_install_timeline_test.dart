import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/info/app_install_timeline.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';

void main() {
  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    // שורש נתונים שאינו קיים חוסם את גזירת תאריך ההתקנה מהדיסק — הבדיקות
    // מאמתות את מסלול הרישום בלבד.
    AppPaths.debugOverrideDataRootPath(
      p.join(Directory.systemTemp.path, 'otzaria-install-timeline-missing'),
    );
  });

  tearDown(() {
    AppPaths.debugOverrideDataRootPath(null);
  });

  group('AppInstallTimelineStore', () {
    test('הפעלה ראשונה רושמת תאריך התקנה ולא תאריך עדכון', () async {
      final now = DateTime.parse('2026-08-20T10:00:00.000');

      await AppInstallTimelineStore.recordLaunch('1.0.0', now: now);
      final timeline = AppInstallTimelineStore.read();

      expect(timeline.installedAt, now);
      expect(timeline.installedAtSource, InstallDateSource.recorded);
      expect(timeline.updatedAt, isNull);
      expect(timeline.previousVersion, isNull);
    });

    test('הפעלה חוזרת באותה גרסה אינה משנה כלום', () async {
      final first = DateTime.parse('2026-08-20T10:00:00.000');
      final second = DateTime.parse('2026-08-21T10:00:00.000');

      await AppInstallTimelineStore.recordLaunch('1.0.0', now: first);
      await AppInstallTimelineStore.recordLaunch('1.0.0', now: second);
      final timeline = AppInstallTimelineStore.read();

      expect(timeline.installedAt, first);
      expect(timeline.updatedAt, isNull);
    });

    test('שינוי גרסה רושם תאריך עדכון וגרסה קודמת', () async {
      final installed = DateTime.parse('2026-08-20T10:00:00.000');
      final updated = DateTime.parse('2026-09-01T08:30:00.000');

      await AppInstallTimelineStore.recordLaunch('1.0.0', now: installed);
      await AppInstallTimelineStore.recordLaunch('1.1.0', now: updated);
      final timeline = AppInstallTimelineStore.read();

      expect(timeline.installedAt, installed);
      expect(timeline.updatedAt, updated);
      expect(timeline.previousVersion, '1.0.0');
    });

    test('עדכון שני דורס את העדכון הקודם', () async {
      await AppInstallTimelineStore.recordLaunch(
        '1.0.0',
        now: DateTime.parse('2026-08-20T10:00:00.000'),
      );
      await AppInstallTimelineStore.recordLaunch(
        '1.1.0',
        now: DateTime.parse('2026-09-01T08:00:00.000'),
      );
      final third = DateTime.parse('2026-10-01T08:00:00.000');
      await AppInstallTimelineStore.recordLaunch('1.2.0', now: third);

      final timeline = AppInstallTimelineStore.read();
      expect(timeline.updatedAt, third);
      expect(timeline.previousVersion, '1.1.0');
    });

    test('ללא רישום כלל — הכל ריק ומקור התאריך unknown', () {
      final timeline = AppInstallTimelineStore.read();

      expect(timeline.installedAt, isNull);
      expect(timeline.installedAtSource, InstallDateSource.unknown);
      expect(timeline.updatedAt, isNull);
    });

    test("גרסה 'unknown' או ריקה אינה נרשמת כלל", () async {
      // ErrorLogFile.appVersion נופל ל-'unknown' כשקריאת PackageInfo נכשלת;
      // רישומה היה מייצר "עדכון" מזויף בהפעלה הבאה.
      for (final version in ['unknown', '', '   ']) {
        await AppInstallTimelineStore.recordLaunch(
          version,
          now: DateTime.parse('2026-08-20T10:00:00.000'),
        );
      }

      final timeline = AppInstallTimelineStore.read();
      expect(timeline.installedAt, isNull);
      expect(timeline.updatedAt, isNull);
      expect(timeline.previousVersion, isNull);
    });

    test("הפעלה כשולה עם 'unknown' אינה מזייפת עדכון בהפעלה הבאה", () async {
      final first = DateTime.parse('2026-08-20T10:00:00.000');
      await AppInstallTimelineStore.recordLaunch('1.0.0', now: first);

      // כשל PackageInfo באמצע — ואז הפעלה תקינה באותה גרסה.
      await AppInstallTimelineStore.recordLaunch(
        'unknown',
        now: DateTime.parse('2026-08-21T10:00:00.000'),
      );
      await AppInstallTimelineStore.recordLaunch(
        '1.0.0',
        now: DateTime.parse('2026-08-22T10:00:00.000'),
      );

      final timeline = AppInstallTimelineStore.read();
      expect(timeline.installedAt, first);
      expect(timeline.updatedAt, isNull);
      expect(timeline.previousVersion, isNull);
    });
  });
}
