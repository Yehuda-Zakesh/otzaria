import 'dart:io';

/// נעילת מופע יחיד לפי קובץ, מוחזקת עד סוף התהליך.
///
/// ב-Windows ה-runner אוכף מופע יחיד ב-mutex לפני עליית המנוע, ולכן זה
/// משמש רק את לינוקס, שה-runner שלה מוגדר `G_APPLICATION_NON_UNIQUE`.
abstract final class SingleInstanceLock {
  static RandomAccessFile? _held;

  /// נתיב הנעילה שבו השתמשה גם החבילה הקודמת, כדי שגרסה ישנה וחדשה יזהו זו את זו.
  static String linuxLockPath(String key) => '/tmp/$key.pid.lock';

  /// true אם התהליך מחזיק עכשיו בנעילה; false רק אם תהליך אחר מחזיק בה.
  ///
  /// כשאי אפשר לפתוח את הקובץ (הרשאות, תיקייה חסרה) ממשיכים כמופע ראשון.
  static Future<bool> acquire(String path) async {
    if (_held != null) return true;
    final RandomAccessFile file;
    try {
      file = await File(path).open(mode: FileMode.write);
    } on FileSystemException {
      return true;
    }
    try {
      _held = await file.lock(FileLock.exclusive);
      return true;
    } on FileSystemException {
      await file.close();
      return false;
    }
  }
}
