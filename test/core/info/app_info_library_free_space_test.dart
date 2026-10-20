import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';

void main() {
  group('libraryFreeSpaceBytes', () {
    test('מחזיר את המקום הפנוי בכונן של נתיב הספרייה', () async {
      String? asked;
      final free = await AppInfoService.libraryFreeSpaceBytes(
        '/storage/emulated/0/books',
        diskSpace: (path) async {
          asked = path;
          return const DiskSpaceInfo(volumeId: '/dev/fuse', freeBytes: 4096);
        },
      );

      expect(asked, '/storage/emulated/0/books');
      expect(free, 4096);
    });

    test('מקום לא ידוע יוצא null ולא -1', () async {
      expect(
        await AppInfoService.libraryFreeSpaceBytes(
          '/x',
          diskSpace: (_) async => DiskSpaceInfo.unknown,
        ),
        isNull,
      );
    });

    test('נתיב אמיתי מחזיר מספר חיובי', () async {
      expect(
        await AppInfoService.libraryFreeSpaceBytes(Directory.systemTemp.path),
        greaterThan(0),
      );
    });
  });
}
