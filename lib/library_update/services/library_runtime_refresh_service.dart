import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// מרענן את מקור הספרייה והמטמונים אחרי עדכון המסד; האינדוקס באחריות ה-BLoC.
class LibraryRuntimeRefreshService {
  const LibraryRuntimeRefreshService();

  /// קוראים אחרי החלפת/עדכון `seforim.db`, בתוך אותו תור פעולות ה-DB.
  Future<void> refreshAfterDbUpdate() async {
    await resetLibraryRuntimeState();

    // פתיחה מחדש של ה-DB החדש (read-only) לקריאות הבאות.
    await SqliteDataProvider.instance.initialize();
  }
}
