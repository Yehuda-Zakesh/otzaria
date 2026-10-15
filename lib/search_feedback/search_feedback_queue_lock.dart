import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FD-scoped Unix flock also excludes other Flutter engines in this process.
/// FileLock on POSIX is process-scoped and cannot protect independent isolates.
class SearchFeedbackQueueLock {
  SearchFeedbackQueueLock._(this._file, this._fd);
  final RandomAccessFile? _file;
  final int? _fd;

  static final _native = DynamicLibrary.process();
  static final _open = _native
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  static final _flock = _native
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'flock',
      );
  static final _close = _native
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _errno = _native
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );

  static Future<SearchFeedbackQueueLock> acquire(String path) async {
    final file = await File(path).open(mode: FileMode.append);
    if (Platform.isWindows) {
      try {
        await file.lock(FileLock.blockingExclusive);
        return SearchFeedbackQueueLock._(file, null);
      } catch (_) {
        await file.close();
        rethrow;
      }
    }
    await file.close();
    final name = path.toNativeUtf8();
    late final int fd;
    try {
      fd = _open(name, 2); // O_RDWR; creation above avoids variadic open().
    } finally {
      calloc.free(name);
    }
    if (fd < 0) throw FileSystemException('open queue lock', path);
    try {
      while (_flock(fd, 2) != 0) {
        // LOCK_EX, blocks only this worker isolate.
        if (_errno().value != 4) {
          // EINTR
          throw FileSystemException('flock queue lock', path);
        }
      }
      return SearchFeedbackQueueLock._(null, fd);
    } catch (_) {
      _close(fd);
      rethrow;
    }
  }

  Future<void> release() async {
    final file = _file;
    if (file != null) {
      try {
        await file.unlock();
      } finally {
        await file.close();
      }
    } else {
      try {
        _flock(_fd!, 8); // LOCK_UN; close also releases it after a crash.
      } finally {
        _close(_fd!);
      }
    }
  }
}
