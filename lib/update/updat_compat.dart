// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Derived from package:updat 1.4.0 (https://github.com/aguilaair/updat).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// מצבי זרימת העדכון של התוכנה.
enum UpdatStatus {
  available,
  availableWithChangelog,
  checking,
  upToDate,
  error,
  idle,
  downloading,
  readyToInstall,
  dismissed,
}

/// פותח את קובץ ההתקנה [file] באפליקציה המשויכת לו במערכת.
///
/// עבור zip נפתח הקובץ הראשון בתיקייה `<תיקיית ה-zip>/[appName]` שאליה חולץ
/// (ב-Windows — קובץ ה-exe הראשון).
Future<void> openInstaller(File file, String appName) async {
  if (!file.existsSync()) {
    throw Exception('Installer does not exists, you have to download it first');
  }
  if (file.path.endsWith('zip')) {
    final outDir = Directory(p.join(p.dirname(file.path), appName));
    file = File(
      outDir
          .listSync()
          .firstWhere((e) => !Platform.isWindows || e.path.endsWith('exe'))
          .path,
    );
  }
  final uri = Uri(path: file.absolute.path, scheme: 'file');
  if (!await canLaunchUrl(uri)) throw 'Error';
  await launchUrl(uri);
}
