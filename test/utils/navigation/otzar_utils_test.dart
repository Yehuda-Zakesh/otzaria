import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/navigation/otzar_utils.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';

class _FailingLocalLauncher extends UrlLauncherPlatform {
  final launched = <String>[];
  final fallback = Completer<void>();

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    if (url.startsWith('OtzarBook:')) return false;
    fallback.complete();
    return true;
  }
}

class _OtzarDirectory extends Fake implements Directory {
  _OtzarDirectory(this.path);
  @override
  final String path;

  @override
  Future<bool> exists() async => true;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.value(_OtzarDirectory('/Volumes/test-drive'));
}

class _OtzarFile extends Fake implements File {
  _OtzarFile(this.path);
  @override
  final String path;

  @override
  Future<bool> exists() async => path == '/Volumes/test-drive/books/7.book';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('כשל בפתיחה מקומית עובר לאתר בלי שגיאה לא מטופלת', () async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _FailingLocalLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await IOOverrides.runZoned(
      () async {
        expect(await OtzarUtils.openBook(7, 'https://otzar.example/7'), isTrue);
        await launcher.fallback.future;
        await Future<void>.delayed(Duration.zero);
        expect(launcher.launched, [
          startsWith('OtzarBook://book/7/'),
          'https://otzar.example/7',
        ]);
      },
      createDirectory: _OtzarDirectory.new,
      createFile: _OtzarFile.new,
    );
  }, skip: !Platform.isMacOS);

  group('macBookUri', () {
    test('הכתובת בפורמט שמטפל הפרוטוקול של אוצר החכמה מקבל', () {
      expect(
        OtzarUtils.macBookUri(151130, tabId: 42),
        'OtzarBook://book/151130/p/1/t/42/fs/0/start/0/end/0/c',
      );
    });

    test('בלי רווח — כתובת שעוברת ב-LaunchServices', () {
      // הרווח שלפני `/c` במסלול Windows תקין שם כי ה-URI הוא ארגומנט תהליך;
      // בכתובת הוא היה נחתך.
      expect(OtzarUtils.macBookUri(1, tabId: 0), isNot(contains(' ')));
    });

    test('מזהה הכרטיסייה מוגרל כשאינו מועבר', () {
      final first = OtzarUtils.macBookUri(7);
      final second = OtzarUtils.macBookUri(7);
      expect(first, startsWith('OtzarBook://book/7/p/1/t/'));
      expect(second, startsWith('OtzarBook://book/7/p/1/t/'));
      expect(first, endsWith('/fs/0/start/0/end/0/c'));
    });
  });

  group('checkBookExistence', () {
    test('מחוץ ל-Windows ולמק אין סריקה — מחזיר false', () async {
      if (Platform.isWindows || Platform.isMacOS) return;
      expect(await OtzarUtils.checkBookExistence(1), isFalse);
    });

    test('במק ספר שאינו על שום כונן מעוגן מחזיר false', () async {
      if (!Platform.isMacOS) return;
      // מזהה שלא סביר שקיים בכונן כלשהו.
      expect(await OtzarUtils.checkBookExistence(999999999), isFalse);
    });
  });
}
