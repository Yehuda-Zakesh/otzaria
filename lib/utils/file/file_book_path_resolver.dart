import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

String resolveMovedFileBookPath(String filePath) {
  if (File(filePath).existsSync()) return filePath;

  final libraryPath =
      Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '';
  if (libraryPath.isEmpty) return filePath;

  final candidates = <String>{};
  final segments = p.split(p.normalize(filePath));

  void addCandidateFromSegment(String segment) {
    final index = segments.lastIndexWhere(
      (part) => part.toLowerCase() == segment.toLowerCase(),
    );
    if (index < 0 || index + 1 >= segments.length) return;
    candidates.add(p.joinAll([libraryPath, ...segments.skip(index + 1)]));
  }

  addCandidateFromSegment(p.basename(libraryPath));
  addCandidateFromSegment(DatabaseConstants.talmudBavliFolderName);

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return filePath;
}
