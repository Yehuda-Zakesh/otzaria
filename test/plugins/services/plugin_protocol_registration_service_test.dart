import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_protocol_registration_service.dart';
import 'package:win32_registry/win32_registry.dart';

void main() {
  group('PluginProtocolRegistrationService', () {
    test(
      'buildWindowsRegistrationEntries uses executable for icon and open command',
      () {
        final entries =
            PluginProtocolRegistrationService.buildWindowsRegistrationEntries(
              r'C:\Program Files\Otzaria\otzaria.exe',
            );

        expect(entries.length, greaterThanOrEqualTo(4));
        expect(entries[2], (
          subkey: r'otzaria\DefaultIcon',
          name: '',
          value: const StringValue(r'C:\Program Files\Otzaria\otzaria.exe'),
        ));
        expect(entries[3], (
          subkey: r'otzaria\shell\open\command',
          name: '',
          value: const StringValue(
            r'"C:\Program Files\Otzaria\otzaria.exe" "%1"',
          ),
        ));
      },
    );

    test('buildWindowsRegistrationEntries מגדיר את פרוטוקול otzaria://', () {
      final entries =
          PluginProtocolRegistrationService.buildWindowsRegistrationEntries(
            r'C:\Program Files\Otzaria\otzaria.exe',
          );

      // בלי הערך הריק 'URL Protocol' — Windows לא מזהה את המפתח כפרוטוקול.
      expect(
        entries,
        contains((
          subkey: 'otzaria',
          name: 'URL Protocol',
          value: const StringValue(''),
        )),
        reason: 'חסר הסימון שהופך את המפתח ל-URL protocol',
      );
    });

    test('buildWindowsRegistrationEntries כולל שיוך קובץ .otzplugin', () {
      final entries =
          PluginProtocolRegistrationService.buildWindowsRegistrationEntries(
            r'C:\Program Files\Otzaria\otzaria.exe',
          );

      // פקודת open של ה-ProgID — פותחת את אוצריא בלחיצה על קובץ .otzplugin
      expect(
        entries,
        contains((
          subkey: r'OtzariaPluginFile\shell\open\command',
          name: '',
          value: const StringValue(
            r'"C:\Program Files\Otzaria\otzaria.exe" "%1"',
          ),
        )),
        reason: 'חסר הרישום של פקודת open עבור ProgID של ‎.otzplugin',
      );

      // DefaultIcon מצביע על משאב 1 ב-EXE (האייקון הייעודי לתוסף)
      expect(
        entries,
        contains((
          subkey: r'OtzariaPluginFile\DefaultIcon',
          name: '',
          value: const StringValue(r'C:\Program Files\Otzaria\otzaria.exe,1'),
        )),
        reason: 'DefaultIcon חייב להצביע על משאב ‎1 ב-EXE',
      );

      // Extension → ProgID
      expect(
        entries,
        contains((
          subkey: '.otzplugin',
          name: '',
          value: const StringValue('OtzariaPluginFile'),
        )),
        reason: 'חסר הקישור בין סיומת ‎.otzplugin ל-ProgID',
      );

      // EditFlags=FTA_NoRecentDocs — מונע הוספת .otzplugin ל-Jump List
      expect(
        entries,
        contains((
          subkey: 'OtzariaPluginFile',
          name: 'EditFlags',
          value: const DwordValue(0x00100000),
        )),
        reason: 'חסר דגל FTA_NoRecentDocs שמונע כניסה ל"מסמכים אחרונים"',
      );
    });

    test('כל המפתחות יחסיים — בלי קידומת hive', () {
      final entries =
          PluginProtocolRegistrationService.buildWindowsRegistrationEntries(
            r'C:\otzaria.exe',
          );
      for (final entry in entries) {
        expect(entry.subkey, isNot(startsWith('HKCU')));
        expect(entry.subkey, isNot(contains('Software\\Classes')));
      }
    });

    // "פרוטוקול מהימן" באופיס (issue #1167)
    test('buildOfficeTrustedProtocolKeys מכסה את כל גרסאות האופיס', () {
      final keys =
          PluginProtocolRegistrationService.buildOfficeTrustedProtocolKeys();

      expect(keys, hasLength(4));
      for (final version in const ['12.0', '14.0', '15.0', '16.0']) {
        expect(
          keys,
          contains(
            'Software\\Policies\\Microsoft\\Office\\$version\\Common\\Security\\'
            'Trusted Protocols\\All Applications\\otzaria:',
          ),
          reason: 'חסר מפתח פרוטוקול מהימן עבור Office $version',
        );
      }
    });

    test('שם המפתח מסתיים בנקודתיים — בלעדיהן אופיס לא מזהה את הפרוטוקול', () {
      final keys =
          PluginProtocolRegistrationService.buildOfficeTrustedProtocolKeys();

      for (final key in keys) {
        expect(key, endsWith('otzaria:'));
        expect(key, isNot(startsWith('HKCU')));
      }
    });

    test('buildLinuxDesktopEntry does not add leading or empty lines', () {
      final entry = PluginProtocolRegistrationService.buildLinuxDesktopEntry(
        executable: '/opt/otzaria/otzaria',
        scheme: 'otzaria',
      );

      final lines = entry.split('\n');
      expect(lines.first, '[Desktop Entry]');
      expect(
        lines.where((line) => line.trim().isEmpty).length,
        1,
      );
      expect(lines[lines.length - 2], 'StartupNotify=true');
    });

    test('buildLinuxDesktopEntry includes icon only when provided', () {
      final entry = PluginProtocolRegistrationService.buildLinuxDesktopEntry(
        executable: '/opt/otzaria/otzaria',
        scheme: 'otzaria',
        iconPath: '/opt/otzaria/icon.png',
      );

      expect(entry, contains('Icon=/opt/otzaria/icon.png'));
      expect(entry, contains('Name=Otzaria\nName[he]=אוצריא\n'));
      expect(
        entry.split('\n').where((line) => line.trim().isEmpty).length,
        1,
      );
    });

    test('buildLinuxDesktopEntry מוסיף MIME type של תוסף כשמסופק', () {
      final entry = PluginProtocolRegistrationService.buildLinuxDesktopEntry(
        executable: '/opt/otzaria/otzaria',
        scheme: 'otzaria',
        pluginMimeType: 'application/x-otzaria-plugin',
      );

      expect(
        entry,
        contains(
          'MimeType=x-scheme-handler/otzaria;application/x-otzaria-plugin;',
        ),
      );
    });

    test('buildLinuxMimeXml מייצר תיאור MIME עם glob תקין', () {
      final xml = PluginProtocolRegistrationService.buildLinuxMimeXml(
        mimeType: 'application/x-otzaria-plugin',
        extension: '.otzplugin',
      );

      expect(xml, contains('type="application/x-otzaria-plugin"'));
      expect(xml, contains('<glob pattern="*.otzplugin"/>'));
      expect(xml, isNot(contains('<icon')));
    });

    test('buildLinuxMimeXml משבץ שם אייקון כשמסופק', () {
      final xml = PluginProtocolRegistrationService.buildLinuxMimeXml(
        mimeType: 'application/x-otzaria-plugin',
        extension: '.otzplugin',
        iconName: 'application-x-otzaria-plugin',
      );

      expect(xml, contains('<icon name="application-x-otzaria-plugin"/>'));
    });

    test('markOfficeTrustedProtocols יוצר מפתח לכל גרסת אופיס', () {
      final created = <String>[];
      PluginProtocolRegistrationService.markOfficeTrustedProtocols(created.add);

      expect(
        created,
        PluginProtocolRegistrationService.buildOfficeTrustedProtocolKeys(),
      );
    });

    test(
      'writeWindowsRegistration כותב לרג\'יסטרי האמיתי מתוך Isolate.run',
      () async {
        final root =
            'Software\\OtzariaTest_${DateTime.now().microsecondsSinceEpoch}';
        const exePath = r'C:\Program Files\Otzaria\otzaria.exe';
        try {
          await Isolate.run(
            () => PluginProtocolRegistrationService.writeWindowsRegistration(
              exePath,
              root: '$root\\',
            ),
          );

          final classes = CURRENT_USER.open('$root\\Software\\Classes');
          try {
            for (final entry
                in PluginProtocolRegistrationService.buildWindowsRegistrationEntries(
                  exePath,
                )) {
              expect(
                classes.getValue(entry.name, path: entry.subkey),
                entry.value,
                reason: '${entry.subkey} [${entry.name}]',
              );
            }
          } finally {
            classes.close();
          }
          for (final subkey
              in PluginProtocolRegistrationService.buildOfficeTrustedProtocolKeys()) {
            CURRENT_USER.open('$root\\$subkey').close();
          }
        } finally {
          CURRENT_USER.removeSubkey(root);
        }
      },
      skip: !Platform.isWindows,
    );

    test('כשל הרשאה במפתח מדיניות אינו מפיל את הסימון כולו', () {
      final created = <String>[];
      PluginProtocolRegistrationService.markOfficeTrustedProtocols((subkey) {
        if (subkey.contains('12.0')) {
          throw Exception('HRESULT(0x80070005): Access is denied.');
        }
        created.add(subkey);
      });

      expect(created, hasLength(3));
      expect(created.every((key) => !key.contains('12.0')), isTrue);
    });
  });
}
