import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/unstable/ffi_bindings.dart' as native;

typedef _ExtensionInit =
    Int Function(Pointer<Void>, Pointer<Pointer<Char>>, Pointer<Pointer<Void>>);

// מיקומי vfs_find ו-cancel_auto_extension ב-ABI הקבוע שב-sqlite3ext.h.
const _vfsFindIndex = 141, _cancelAutoExtensionIndex = 195;

Pointer<native.sqlite3_vfs> _findDefaultVfs() {
  late Pointer<native.sqlite3_vfs> result;
  late NativeCallable<_ExtensionInit> extension;
  extension = NativeCallable<_ExtensionInit>.isolateLocal((
    Pointer<Void> db,
    Pointer<Pointer<Char>> error,
    Pointer<Pointer<Void>> api,
  ) {
    api[_cancelAutoExtensionIndex]
        .cast<NativeFunction<Int Function(Pointer<Void>)>>()
        .asFunction<int Function(Pointer<Void>)>()(
      extension.nativeFunction.cast(),
    );
    result = api[_vfsFindIndex]
        .cast<
          NativeFunction<Pointer<native.sqlite3_vfs> Function(Pointer<Char>)>
        >()
        .asFunction<
          Pointer<native.sqlite3_vfs> Function(Pointer<Char>)
        >()(nullptr);
    return 0;
  }, exceptionalReturn: 1);
  native.sqlite3_auto_extension(extension.nativeFunction.cast());
  try {
    sqlite3.openInMemory().close();
    return result;
  } finally {
    extension.close();
  }
}

/// מעביר I/O למערכת הקבצים האמיתית, ומדמה כשל רק במיפוי SHM.
class SqliteShmFailure {
  SqliteShmFailure() {
    _base = _findDefaultVfs();
    _vfs = calloc<native.sqlite3_vfs>();
    _vfs
        .cast<Uint8>()
        .asTypedList(sizeOf<native.sqlite3_vfs>())
        .setAll(
          0,
          _base.cast<Uint8>().asTypedList(sizeOf<native.sqlite3_vfs>()),
        );
    _name = 'otzaria-test-shm-failure'.toNativeUtf8();
    _open =
        NativeCallable<
          Int Function(
            Pointer<native.sqlite3_vfs>,
            Pointer<Char>,
            Pointer<native.sqlite3_file>,
            Int,
            Pointer<Int>,
          )
        >.isolateLocal(_openFile, exceptionalReturn: 10);
    _map =
        NativeCallable<
          Int Function(
            Pointer<native.sqlite3_file>,
            Int,
            Int,
            Int,
            Pointer<Pointer<Void>>,
          )
        >.isolateLocal(_mapShm, exceptionalReturn: 10);
    _close =
        NativeCallable<Int Function(Pointer<native.sqlite3_file>)>.isolateLocal(
          _closeFile,
          exceptionalReturn: 10,
        );
    _vfs.ref
      ..zName = _name.cast()
      ..xOpen = _open.nativeFunction;
    native.sqlite3_vfs_register(_vfs, 1);
  }

  int errorCode = 0;
  int? failMainOpenAt;
  int mainOpens = 0;
  int get openFiles => _methods.length;
  late final Pointer<native.sqlite3_vfs> _base, _vfs;
  late final Pointer<Utf8> _name;
  late final NativeCallable<
    Int Function(
      Pointer<native.sqlite3_vfs>,
      Pointer<Char>,
      Pointer<native.sqlite3_file>,
      Int,
      Pointer<Int>,
    )
  >
  _open;
  late final NativeCallable<
    Int Function(
      Pointer<native.sqlite3_file>,
      Int,
      Int,
      Int,
      Pointer<Pointer<Void>>,
    )
  >
  _map;
  late final NativeCallable<Int Function(Pointer<native.sqlite3_file>)> _close;
  final _methods =
      <
        int,
        (Pointer<native.sqlite3_io_methods>, Pointer<native.sqlite3_io_methods>)
      >{};

  int _openFile(
    Pointer<native.sqlite3_vfs> vfs,
    Pointer<Char> path,
    Pointer<native.sqlite3_file> file,
    int flags,
    Pointer<Int> outFlags,
  ) {
    if (flags & 0x100 != 0 && ++mainOpens == failMainOpenAt) return 14;
    final result =
        _base.ref.xOpen
            .asFunction<
              int Function(
                Pointer<native.sqlite3_vfs>,
                Pointer<Char>,
                Pointer<native.sqlite3_file>,
                int,
                Pointer<Int>,
              )
            >()(
          _base,
          path,
          file,
          flags,
          outFlags,
        );
    if (result == 0 && file.ref.pMethods.ref.iVersion >= 2) {
      final original = file.ref.pMethods;
      final copy = calloc<native.sqlite3_io_methods>();
      copy
          .cast<Uint8>()
          .asTypedList(sizeOf<native.sqlite3_io_methods>())
          .setAll(
            0,
            original.cast<Uint8>().asTypedList(
              sizeOf<native.sqlite3_io_methods>(),
            ),
          );
      _methods[file.address] = (original, copy);
      copy.ref
        ..xShmMap = _map.nativeFunction
        ..xClose = _close.nativeFunction;
      file.ref.pMethods = copy;
    }
    return result;
  }

  int _mapShm(
    Pointer<native.sqlite3_file> file,
    int page,
    int size,
    int write,
    Pointer<Pointer<Void>> output,
  ) {
    if (errorCode != 0) {
      output.value = nullptr;
      return errorCode;
    }
    return _methods[file.address]!.$1.ref.xShmMap
        .asFunction<
          int Function(
            Pointer<native.sqlite3_file>,
            int,
            int,
            int,
            Pointer<Pointer<Void>>,
          )
        >()(file, page, size, write, output);
  }

  int _closeFile(Pointer<native.sqlite3_file> file) {
    final (original, copy) = _methods.remove(file.address)!;
    file.ref.pMethods = original;
    calloc.free(copy);
    return original.ref.xClose
        .asFunction<int Function(Pointer<native.sqlite3_file>)>()(file);
  }

  void dispose() {
    if (_methods.isNotEmpty) throw StateError('SQLite files still open');
    native.sqlite3_vfs_unregister(_vfs);
    native.sqlite3_vfs_register(_base, 1);
    _open.close();
    _map.close();
    _close.close();
    calloc.free(_vfs);
    calloc.free(_name);
  }
}
