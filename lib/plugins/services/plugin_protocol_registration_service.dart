import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:win32_registry/win32_registry.dart';

/// רשומת רישום אחת ב-Windows: מפתח יחסי ל-`HKCU\Software\Classes`, שם ערך
/// ('' = ערך ברירת המחדל של המפתח) והערך עצמו.
typedef WindowsRegistrationEntry = ({
  String subkey,
  String name,
  RegistryValue value,
});

class PluginProtocolRegistrationService {
  static const String scheme = 'otzaria';
  static const String pluginFileExtension = '.otzplugin';
  static const String pluginFileProgId = 'OtzariaPluginFile';
  static const String pluginMimeType = 'application/x-otzaria-plugin';

  /// אותו שם כמו בחבילות deb/rpm, כדי שהשיוכים הקיימים יצביעו עליו.
  static const String desktopFileName = 'otzaria.desktop';

  /// גרסאות Office שעבורן נרשם `otzaria:` כפרוטוקול מהימן:
  /// 12.0=2007, 14.0=2010, 15.0=2013, 16.0=2016 ואילך (כולל Microsoft 365).
  static const List<String> officeVersions = ['12.0', '14.0', '15.0', '16.0'];

  Future<void> ensureRegistered() async {
    // במצב נייד אין לרשום שיוכים מערכתיים: הרישום מצביע על נתיב EXE
    // שעלול להיעלם (דיסק-און-קי), ומשאיר שאריות ברגיסטרי/desktop של כל
    // מחשב מארח. התקנת תוספים עדיין זמינה דרך הממשק הפנימי.
    if (AppPaths.isPortable) {
      return;
    }

    if (Platform.isWindows) {
      await _ensureWindowsRegistration();
      return;
    }

    if (Platform.isLinux) {
      await _ensureLinuxRegistration();
    }
  }

  // ⚠️ ב-isolate נפרד: קריאות הרג'יסטרי סינכרוניות (FFI), ורג'יסטרי איטי
  // (אנטי-וירוס, hive נודד) היה מקפיא את ה-UI כולו (issue #1549).
  Future<void> _ensureWindowsRegistration() {
    final exePath = Platform.resolvedExecutable;
    return Isolate.run(() => writeWindowsRegistration(exePath));
  }

  /// [root] הוא קידומת יחסית ל-HKCU לכל המפתחות; ריקה בשימוש אמיתי.
  @visibleForTesting
  static void writeWindowsRegistration(String exePath, {String root = ''}) {
    for (final entry in buildWindowsRegistrationEntries(exePath)) {
      final key = CURRENT_USER.create(
        '${root}Software\\Classes\\${entry.subkey}',
      );
      try {
        // כותבים רק ערך שונה: אנטי-וירוס מאט כתיבות לכאן (issue #1549).
        if (key.getValue(entry.name) != entry.value) {
          key.setValue(entry.name, entry.value);
        }
      } finally {
        key.close();
      }
    }

    markOfficeTrustedProtocols(
      (subkey) => CURRENT_USER.create('$root$subkey').close(),
    );
  }

  /// המפתחות עצמם הם הסימון — אופיס בודק רק את קיומם, בלי ערך בתוכם.
  ///
  /// ⚠️ תוספת קוסמטית בלבד: היא חוסכת אזהרת אבטחה, ולא נדרשת לפתיחת קישורים.
  /// ב-`HKCU\Software\Policies` אין למשתמש הרשאת כתיבה במחשב מנוהל, ולכן כשל
  /// שם אינו כשל רישום ואסור לו לזהם את יומן השגיאות בכל הפעלה.
  @visibleForTesting
  static void markOfficeTrustedProtocols(void Function(String subkey) create) {
    for (final subkey in buildOfficeTrustedProtocolKeys()) {
      try {
        create(subkey);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('סימון פרוטוקול מהימן באופיס נכשל עבור $subkey: $error');
        }
      }
    }
  }

  /// מפתחות "פרוטוקול מהימן" של אופיס (יחסית ל-HKCU), שמונעים את אזהרת
  /// האבטחה בלחיצה על קישור `otzaria://` מתוך מסמך (issue #1167).
  @visibleForTesting
  static List<String> buildOfficeTrustedProtocolKeys() => [
    for (final version in officeVersions)
      'Software\\Policies\\Microsoft\\Office\\$version\\Common\\Security\\'
          'Trusted Protocols\\All Applications\\$scheme:',
  ];

  Future<void> _ensureLinuxRegistration() async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) {
      throw Exception('לא ניתן לאתר את תיקיית הבית לרישום פרוטוקול בלינוקס');
    }

    final applicationsDir = Directory(
      p.join(home, '.local', 'share', 'applications'),
    );

    final mimePackagesDir = Directory(
      p.join(home, '.local', 'share', 'mime', 'packages'),
    );
    await mimePackagesDir.create(recursive: true);

    final desktopFile = File(p.join(applicationsDir.path, desktopFileName));
    final executable = AppPaths.launchExecutable;
    final iconPath = p.join(
      p.dirname(executable),
      'data',
      'flutter_assets',
      'assets',
      'icon',
      'iconnew.png',
    );
    final existingEntry = await desktopFile.exists()
        ? utf8.decode(await desktopFile.readAsBytes(), allowMalformed: true)
        : null;
    final desktopFileIsOurs =
        existingEntry == null ||
        isGeneratedLinuxDesktopEntry(
          existingEntry,
          executables: {executable, Platform.resolvedExecutable},
          iconPath: iconPath,
        );
    // קובץ באותו שם ב-~/.local/share/applications דורס את זה של החבילה,
    // ושייך למשתמש. נוגעים רק בעותק שהאפליקציה עצמה כתבה ולא שונה.
    final hasSystemEntry = hasSystemLinuxDesktopEntry(
      Platform.environment['XDG_DATA_DIRS'],
      userDesktopFile: desktopFile.path,
    );
    final writesDesktopFile = desktopFileIsOurs && !hasSystemEntry;
    final removesDesktopFile =
        existingEntry != null && desktopFileIsOurs && hasSystemEntry;

    if (writesDesktopFile) {
      await applicationsDir.create(recursive: true);
      await desktopFile.writeAsString(
        buildLinuxDesktopEntry(
          executable: executable,
          scheme: scheme,
          pluginMimeType: pluginMimeType,
          iconPath: File(iconPath).existsSync() ? iconPath : null,
        ),
        flush: true,
      );
    } else if (removesDesktopFile) {
      await desktopFile.delete();
    }

    // שם האייקון שיוטמע ב-XML של ה-MIME וייעתק לתיקיית האייקונים.
    // freedesktop ממיר את שם ה-MIME (`application/x-otzaria-plugin`) ל-
    // `application-x-otzaria-plugin` כשהוא מחפש אייקון.
    const mimeIconName = 'application-x-otzaria-plugin';

    final mimeDir = p.join(home, '.local', 'share', 'mime');
    final mimeFile = File(p.join(mimePackagesDir.path, 'otzaria-plugin.xml'));
    final mimeChanged = await writeIfChanged(
      mimeFile,
      buildLinuxMimeXml(
        mimeType: pluginMimeType,
        extension: pluginFileExtension,
        iconName: mimeIconName,
      ),
    );

    // ===== רישום קריטי — חייב להצליח =====
    // הקובץ ש-update-mime-database מייצר מעיד שריצה קודמת לא נכשלה באמצע.
    final mimeCompiled = File(p.join(mimeDir, '$pluginMimeType.xml'));
    if (mimeChanged || !await mimeCompiled.exists()) {
      await _runLinuxCommandIfAvailable('update-mime-database', [mimeDir]);
    }
    if (writesDesktopFile || removesDesktopFile) {
      await _runLinuxCommandIfAvailable('update-desktop-database', [
        applicationsDir.path,
      ]);
    }
    if (writesDesktopFile) {
      await _runLinuxCommandIfAvailable('xdg-mime', [
        'default',
        desktopFileName,
        'x-scheme-handler/$scheme',
      ]);
      await _runLinuxCommandIfAvailable('xdg-mime', [
        'default',
        desktopFileName,
        pluginMimeType,
      ]);
    }

    // ===== אייקון — תוספת קוסמטית =====
    // נריץ אחרי הרישום הקריטי וניתן ל-failures להיבלע, כדי שכשל
    // ב-gtk-update-icon-cache (למשל בלי index.theme) לא יבטל את השיוך עצמו.
    try {
      await _installLinuxMimeIcon(home, mimeIconName, executable);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'התקנת אייקון MIME בלינוקס נכשלה (לא קריטי): $error\n$stackTrace',
        );
      }
    }
  }

  /// מעתיק את `otzplugin_file_icon.png` (256×256) ל-
  /// `~/.local/share/icons/hicolor/256x256/mimetypes/<mimeIconName>.png` ומרענן
  /// את מטמון האייקונים. אם קובץ המקור לא קיים — נדלג בשקט (התקנה
  /// פיתוחית/לא רגילה), והמערכת תציג אייקון גנרי.
  Future<void> _installLinuxMimeIcon(
    String home,
    String mimeIconName,
    String executable,
  ) async {
    final sourceIcon = File(
      p.join(
        p.dirname(executable),
        'data',
        'flutter_assets',
        'assets',
        'icon',
        'otzplugin_file_icon.png',
      ),
    );
    if (!await sourceIcon.exists()) {
      return;
    }

    final iconsRoot = p.join(home, '.local', 'share', 'icons', 'hicolor');
    final mimetypesDir = Directory(p.join(iconsRoot, '256x256', 'mimetypes'));
    await mimetypesDir.create(recursive: true);

    final destination = File(p.join(mimetypesDir.path, '$mimeIconName.png'));
    if (await destination.exists() &&
        listEquals(
          await destination.readAsBytes(),
          await sourceIcon.readAsBytes(),
        )) {
      return;
    }
    await sourceIcon.copy(destination.path);

    // gtk-update-icon-cache דורש index.theme בתיקיית התמה כדי להצליח.
    // ב-~/.local/share/icons/hicolor הקובץ הזה בדרך כלל לא קיים (התמה
    // המערכתית יושבת ב-/usr/share/icons/hicolor), אז נריץ רק אם הוא קיים.
    // ה-MIME database עצמו יודע על האייקון דרך mime-info XML, וסביבות
    // עבודה רובן יסרקו מחדש את התיקייה בלי הקריאה הזו.
    final themeIndex = File(p.join(iconsRoot, 'index.theme'));
    if (await themeIndex.exists()) {
      await _runLinuxCommandIfAvailable('gtk-update-icon-cache', [
        '-f',
        '-t',
        iconsRoot,
      ]);
    }
  }

  /// כותב רק כשהתוכן שונה, כדי לא לגעת בכל הפעלה בקבצים שכבר מעודכנים.
  /// מחזיר האם נכתב.
  @visibleForTesting
  static Future<bool> writeIfChanged(File file, String content) async {
    if (await file.exists() &&
        utf8.decode(await file.readAsBytes(), allowMalformed: true) ==
            content) {
      return false;
    }
    await file.writeAsString(content, flush: true);
    return true;
  }

  Future<void> _runLinuxCommandIfAvailable(
    String executable,
    List<String> arguments,
  ) async {
    final lookup = await Process.run('which', [executable], runInShell: true);
    if (lookup.exitCode != 0) {
      return;
    }

    final result = await Process.run(executable, arguments, runInShell: true);
    if (result.exitCode != 0) {
      throw Exception(
        'רישום פרוטוקול בלינוקס נכשל עבור $executable: ${result.stderr}'.trim(),
      );
    }
  }

  @visibleForTesting
  static String buildLinuxDesktopEntry({
    required String executable,
    required String scheme,
    String? pluginMimeType,
    String? iconPath,
  }) {
    final mimeTypes = <String>[
      'x-scheme-handler/$scheme',
      if (pluginMimeType != null && pluginMimeType.trim().isNotEmpty)
        pluginMimeType,
    ];

    final lines = <String>[
      '[Desktop Entry]',
      'Version=1.0',
      'Type=Application',
      'Name=Otzaria',
      'Name[he]=אוצריא',
      'Exec="$executable" %u',
      'Terminal=false',
      'MimeType=${mimeTypes.join(';')};',
      'Categories=Education;Utility;',
      'StartupNotify=true',
      if (iconPath != null && iconPath.trim().isNotEmpty) 'Icon=$iconPath',
    ];

    return '${lines.join('\n')}\n';
  }

  /// האם [content] זהה למה שהאפליקציה עצמה כותבת, כלומר המשתמש לא ערך אותו.
  @visibleForTesting
  static bool isGeneratedLinuxDesktopEntry(
    String content, {
    required Iterable<String> executables,
    required String iconPath,
  }) {
    for (final executable in executables) {
      for (final icon in [iconPath, null]) {
        final entry = buildLinuxDesktopEntry(
          executable: executable,
          scheme: scheme,
          pluginMimeType: pluginMimeType,
          iconPath: icon,
        );
        // גרסאות עד 0.10.4 כתבו את השם העברי בלבד.
        final hebrewOnlyEntry = entry.replaceFirst(
          'Name=Otzaria\nName[he]=',
          'Name=',
        );
        if (content == entry || content == hebrewOnlyEntry) return true;
      }
    }
    return false;
  }

  /// האם חבילת deb/rpm התקינה [desktopFileName] בתיקיות הנתונים של המערכת
  /// ([xdgDataDirs] לפי XDG). [userDesktopFile] אינו נחשב, גם אם תיקייתו ברשימה.
  @visibleForTesting
  static bool hasSystemLinuxDesktopEntry(
    String? xdgDataDirs, {
    required String userDesktopFile,
  }) {
    final dataDirs = (xdgDataDirs == null || xdgDataDirs.trim().isEmpty)
        ? '/usr/local/share:/usr/share'
        : xdgDataDirs;
    return dataDirs.split(':').where((dir) => dir.isNotEmpty).any((dir) {
      final path = p.join(dir, 'applications', desktopFileName);
      return !p.equals(path, userDesktopFile) && File(path).existsSync();
    });
  }

  @visibleForTesting
  static String buildLinuxMimeXml({
    required String mimeType,
    required String extension,
    String? iconName,
  }) {
    final pattern = extension.startsWith('.') ? '*$extension' : '*.$extension';
    final iconLine = (iconName != null && iconName.trim().isNotEmpty)
        ? '    <icon name="$iconName"/>\n'
        : '';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="$mimeType">
    <comment>Otzaria plugin package</comment>
    <comment xml:lang="he">חבילת תוסף אוצריא</comment>
$iconLine    <glob pattern="$pattern"/>
  </mime-type>
</mime-info>
''';
  }

  @visibleForTesting
  static List<WindowsRegistrationEntry> buildWindowsRegistrationEntries(
    String exePath,
  ) {
    final command = StringValue('"$exePath" "%1"');
    const protocolRoot = scheme;
    const progIdRoot = pluginFileProgId;
    const extensionRoot = pluginFileExtension;

    return <WindowsRegistrationEntry>[
      // ===== otzaria:// protocol =====
      (
        subkey: protocolRoot,
        name: '',
        value: const StringValue('URL:Otzaria Protocol'),
      ),
      (
        subkey: protocolRoot,
        name: 'URL Protocol',
        value: const StringValue(''),
      ),
      (
        subkey: '$protocolRoot\\DefaultIcon',
        name: '',
        value: StringValue(exePath),
      ),
      (subkey: '$protocolRoot\\shell\\open\\command', name: '', value: command),

      // ===== .otzplugin file association =====
      (subkey: progIdRoot, name: '', value: const StringValue('תוסף אוצריא')),
      // התקנת תוסף היא פעולה חד-פעמית; הדגל FTA_NoRecentDocs (0x00100000)
      // מונע מהמעטפת להוסיף את הקובץ ל"מסמכים אחרונים" / Jump List.
      (
        subkey: progIdRoot,
        name: 'EditFlags',
        value: const DwordValue(0x00100000),
      ),
      // האייקון הייעודי לתוסף משובץ ב-EXE כמשאב שני
      // (IDI_OTZPLUGIN_FILE_ICON ב-Runner.rc); index 1 מצביע עליו.
      (
        subkey: '$progIdRoot\\DefaultIcon',
        name: '',
        value: StringValue('$exePath,1'),
      ),
      (subkey: '$progIdRoot\\shell\\open\\command', name: '', value: command),
      (
        subkey: extensionRoot,
        name: '',
        value: const StringValue(pluginFileProgId),
      ),
      (
        subkey: extensionRoot,
        name: 'Content Type',
        value: const StringValue(pluginMimeType),
      ),
    ];
  }
}
