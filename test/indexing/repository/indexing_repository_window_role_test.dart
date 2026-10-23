import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// אינדקס החיפוש משותף לכל החלונות של התהליך, והחלון הראשון הוא היחיד
/// שיכול לבנות אותו מחדש. מחיקה מחלון משני השאירה אותו מחוק ובלי בונה —
/// וב-Windows גם חצי-מחוק, כי החלון הראשון מחזיק handles על אותם קבצים.
void main() {
  // `clearIndex` מציג `UiSnack` בסירוב, וזה נוגע ב-`WidgetsBinding`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingProvider provider;
  late IndexingRepository repository;

  setUp(() {
    provider = _RecordingProvider();
    repository = IndexingRepository(provider);
  });

  tearDown(() {
    WindowRole.isSecondary = false;
    ProcessDuties.debugOverride = null;
  });

  group('חלון משני', () {
    setUp(() => WindowRole.isSecondary = true);

    test('clearIndex מסרב ואינו נוגע באינדקס', () async {
      expect(await repository.clearIndex(), isFalse);
      expect(provider.clearCount, 0);
    });

    test('dropBookIndexEntries מחזיר false בלי לגעת במנוע', () async {
      final dropped = await repository.dropBookIndexEntries([
        TextBook(title: 'ספר'),
      ]);
      expect(dropped, isFalse);
    });

    test('dropOrphanedIndexEntries מחזיר 0 בלי לגעת במנוע', () async {
      final removed = await repository.dropOrphanedIndexEntries(
        Library(categories: []),
      );
      expect(removed, 0);
    });
  });

  // ההחלטה היא של ProcessDuties: הוא גובר על תפקיד החלון בשני הכיוונים.
  group('בעלות לפי ProcessDuties', () {
    test('לא-בעלים מסרב גם כשהחלון ראשי', () async {
      ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
      expect(await repository.clearIndex(), isFalse);
      expect(
        await repository.dropBookIndexEntries([TextBook(title: 'ספר')]),
        isFalse,
      );
      expect(provider.clearCount, 0);
    });

    test('בעלים מוחק גם כשהחלון משני', () async {
      WindowRole.isSecondary = true;
      ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => true);
      expect(await repository.clearIndex(), isTrue);
      expect(provider.clearCount, 1);
    });
  });

  group('חלון ראשי (בקרה)', () {
    setUp(() => WindowRole.isSecondary = false);

    test('clearIndex כן מוחק', () async {
      expect(await repository.clearIndex(), isTrue);
      expect(provider.clearCount, 1);
    });
  });
}

class _RecordingProvider implements TantivyDataProvider {
  int clearCount = 0;

  @override
  final Set<String> indexedFilePaths = <String>{};

  @override
  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(false);

  @override
  Future<void> clear() async {
    clearCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('Unexpected call: $invocation');
  }
}
