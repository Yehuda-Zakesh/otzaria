import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/single_instance_lock.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('single_instance_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // הנעילה המוחזקת עד סוף התהליך חוסמת מחיקה ב-Windows.
    }
  });

  test('a lock file that cannot be opened does not block startup', () async {
    final path = p.join(tmp.path, 'missing', 'otzaria.pid.lock');
    expect(await SingleInstanceLock.acquire(path), isTrue);
  });

  test(
    'reports a second instance while another handle holds the lock',
    () async {
      final path = p.join(tmp.path, 'otzaria.pid.lock');
      final other = await File(path).open(mode: FileMode.write);
      await other.lock(FileLock.exclusive);
      try {
        expect(await SingleInstanceLock.acquire(path), isFalse);
      } finally {
        await other.close();
      }
    },
    // ב-POSIX נעילת fcntl שייכת לתהליך, ולכן אי אפשר להתנגש בה מאותו תהליך.
    skip: !Platform.isWindows,
  );

  test('acquires a free lock and keeps holding it', () async {
    final path = p.join(tmp.path, 'otzaria.pid.lock');
    expect(await SingleInstanceLock.acquire(path), isTrue);
    expect(File(path).existsSync(), isTrue);
  });

  test('uses the lock path of the previous single-instance package', () {
    expect(
      SingleInstanceLock.linuxLockPath('otzaria'),
      '/tmp/otzaria.pid.lock',
    );
  });
}
