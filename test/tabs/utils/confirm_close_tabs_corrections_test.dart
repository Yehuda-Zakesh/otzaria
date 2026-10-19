import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// כתיבות שנכשלות לפי דגל, מעל מאגר אמיתי בזיכרון.
class _FlakyDrafts implements PluginCorrectionDraftRepository {
  _FlakyDrafts(this.inner);
  final PluginCorrectionDraftRepository inner;
  bool failWrites = false;

  @override
  Future<({String status, int? version, String? conflicts})> write({
    required String pluginId,
    required String draftId,
    required String token,
    required int revision,
    required String libraryVersion,
    required String changesJson,
    String? conflictsJson,
    int? expectedVersion,
  }) async {
    if (failWrites) throw StateError('disk full');
    return inner.write(
      pluginId: pluginId,
      draftId: draftId,
      token: token,
      revision: revision,
      libraryVersion: libraryVersion,
      changesJson: changesJson,
      conflictsJson: conflictsJson,
      expectedVersion: expectedVersion,
    );
  }

  @override
  Future<
    ({String token, int epoch, int? version, String changes, String conflicts})
  >
  acquire({
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
  }) => inner.acquire(
    pluginId: pluginId,
    draftId: draftId,
    bookUid: bookUid,
    bookId: bookId,
    bookSource: bookSource,
    libraryVersion: libraryVersion,
  );

  @override
  Future<({String status, int? version})> rescue({
    required String pluginId,
    required String draftId,
    required String bookUid,
    required String bookId,
    required String bookSource,
    required String libraryVersion,
    required String entriesJson,
    required int sinceEpoch,
  }) async {
    if (failWrites) throw StateError('disk full');
    return inner.rescue(
      pluginId: pluginId,
      draftId: draftId,
      bookUid: bookUid,
      bookId: bookId,
      bookSource: bookSource,
      libraryVersion: libraryVersion,
      entriesJson: entriesJson,
      sinceEpoch: sinceEpoch,
    );
  }

  @override
  Future<void> release({
    required String pluginId,
    required String draftId,
    required String token,
  }) => inner.release(pluginId: pluginId, draftId: draftId, token: token);

  @override
  Future<void> purge(String pluginId) => inner.purge(pluginId);

  int gets = 0;

  @override
  Future<Map<String, Object?>?> get(String pluginId, String draftId) {
    gets++;
    return inner.get(pluginId, draftId);
  }

  @override
  Future<Map<String, Object?>> acknowledge({
    required String pluginId,
    required String draftId,
    required int version,
  }) => inner.acknowledge(
    pluginId: pluginId,
    draftId: draftId,
    version: version,
  );

  @override
  Future<List<Map<String, Object?>>> list(String pluginId) =>
      inner.list(pluginId);

  @override
  Future<void> heartbeat() => inner.heartbeat();

  @override
  Future<void> dispose() => inner.dispose();
}

/// תשובת שמירה נשלטת, בלי מאגר.
class _FakeService extends PluginCorrectionSessionService {
  final Set<String> unpersisted = {};
  final List<Iterable<String>> asked = [];

  @override
  String? ownerNameForTab(String tabId) => 'בודק';
  @override
  bool hasSessionForTab(String tabId) => true;
  @override
  Future<List<({String tabId, String ownerName, String bookId})>>
  unsavedStates({Iterable<String>? tabIds, Duration? timeout}) async {
    if (tabIds != null) asked.add(tabIds.toList());
    return [
      for (final tabId in unpersisted)
        if (tabIds == null || tabIds.contains(tabId))
          (tabId: tabId, ownerName: 'בודק', bookId: 'ברכות'),
    ];
  }
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  TextBookTab textTab() =>
      TextBookTab(book: TextBook(title: 'ברכות'), index: 0);

  group('unpersistedCorrectionTabs עם שירות אמיתי', () {
    late Database db;
    late _FlakyDrafts drafts;
    late PluginCorrectionSessionService service;
    late TextBookTab tab;
    late String tabId;

    setUp(() async {
      db = sqlite3.openInMemory();
      drafts = _FlakyDrafts(PluginCorrectionDraftRepository.direct(db));
      service = PluginCorrectionSessionService()..draftRepository = drafts;
      tab = textTab();
      tabId = PluginCorrectionSessionService.tabIdFor(tab);
      await service.begin(
        owner: 'p1',
        ownerName: 'בודק',
        tabId: tabId,
        bookId: 'ברכות',
        bookUid: 'id:1',
        libraryVersion: 'v1',
        loadSource: (_) async => 'מקור',
      );
    });

    tearDown(() async {
      drafts.failWrites = false;
      service.endAll('test');
      await service.flushAll();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      service.dispose();
      db.close();
    });

    test('טיוטה שנשמרה אינה מחזירה אזהרה', () async {
      service.editParagraph(tabId, 0, 'מקור', 'תיקון');
      final entries = await unpersistedCorrectionTabs([
        CombinedTab(rightTab: tab, leftTab: textTab()),
      ], service: service);
      expect(entries, isEmpty);

      // get קורא את הטיוטה העמידה ומחזיר את הגרסה שלה, לא מדלג על הקריאה.
      final sessionId = service.sessionIdForTab('p1', tabId)!;
      final snapshot = await service.get('p1', sessionId);
      expect(drafts.gets, 1);
      final durable = await service.getDraft(
        'p1',
        snapshot['draft']['draftId'],
      );
      expect(snapshot['draft']['version'], durable['version']);
    });

    test(
      'סיום עריכה לפני שהשמירה הצליחה אינו מסיר את הלשונית מהאזהרה',
      () async {
        drafts.failWrites = true;
        service.editParagraph(tabId, 0, 'מקור', 'תיקון');
        service.endByUser(tabId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(service.hasSessionForTab(tabId), isFalse);
        final entries = await unpersistedCorrectionTabs([
          tab,
        ], service: service);
        expect(entries.single.tab, same(tab));
        expect(entries.single.message, unsavedCorrectionsMessage('בודק'));
      },
    );

    testWidgets(
      'סגירת התוכנה: לשונית שכבר נסגרה עם תיקונים שלא נשמרו מציגה אזהרה, '
      'ואחרי שמירה מוצלחת לא',
      (tester) async {
        PluginCorrectionSessionService.flushTimeout = const Duration(
          milliseconds: 20,
        );
        addTearDown(
          () => PluginCorrectionSessionService.flushTimeout = const Duration(
            seconds: 3,
          ),
        );
        await tester.runAsync(() async {
          drafts.failWrites = true;
          service.editParagraph(tabId, 0, 'מקור', 'תיקון');
          service.removeTab(tabId);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });

        late Future<bool> result;
        Future<void> close() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => result = confirmCloseTabs(
                    context,
                    const [],
                    corrections: service,
                    includeClosedTabCorrections: true,
                  ),
                  child: const Text('close'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('close'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
        }

        await close();
        expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
        expect(find.textContaining('ברכות'), findsOneWidget);
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();
        expect(await result, isFalse);

        // אחרי ניסיון חוזר מוצלח המצב שמור, ואין אזהרה מטעה.
        drafts.failWrites = false;
        await tester.runAsync(() async {
          service.retryDraftWrites();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await close();
        expect(find.text(unsavedChangesDialogTitle), findsNothing);
        expect(await result, isTrue);
      },
    );

    test('טיוטה שלא נשמרה מחזירה את הלשונית עם שם התוסף', () async {
      drafts.failWrites = true;
      service.editParagraph(tabId, 0, 'מקור', 'תיקון');
      final entries = await unpersistedCorrectionTabs([
        tab,
      ], service: service);
      expect(entries.single.tab, same(tab));
      expect(entries.single.message, unsavedCorrectionsMessage('בודק'));
    });
  });

  group('confirmCloseTabs', () {
    late _FakeService service;

    setUp(() => service = _FakeService());
    tearDown(() => service.dispose());

    Future<Future<bool>> pump(WidgetTester tester, TextBookTab tab) async {
      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => result = confirmCloseTabs(
                context,
                [tab],
                corrections: service,
              ),
              child: const Text('close'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('לשונית בלי מזהה אינה נבדקת', (tester) async {
      final result = await pump(tester, textTab());
      expect(service.asked, isEmpty);
      expect(await result, isTrue);
    });

    testWidgets('טיוטה שמורה — סוגר בלי דיאלוג', (tester) async {
      final tab = textTab();
      PluginCorrectionSessionService.tabIdFor(tab);
      final result = await pump(tester, tab);
      expect(service.asked, hasLength(1));
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
      expect(await result, isTrue);
    });

    testWidgets('טיוטה שלא נשמרה — דיאלוג עם ההודעה', (tester) async {
      final tab = textTab();
      service.unpersisted.add(PluginCorrectionSessionService.tabIdFor(tab));
      final result = await pump(tester, tab);
      expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
      expect(
        find.textContaining(unsavedCorrectionsMessage('בודק')),
        findsOneWidget,
      );
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
