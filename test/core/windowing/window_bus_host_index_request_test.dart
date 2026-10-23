import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_bus_host.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

/// כל חלון רשאי **ליזום** אינדוקס, והמארח הוא שמבצע: Tantivy נועל את
/// ה-writer בלעדית, והחלון הראשון מחזיק את הנעילה לכל חיי התהליך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockLibraryBloc libraryBloc;
  late _MockIndexingBloc indexingBloc;
  final library = Library(categories: []);

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUpAll(() => registerFallbackValue(ClearIndex()));

  setUp(() {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = 'otzaria.test.bushost.index';
    libraryBloc = _MockLibraryBloc();
    indexingBloc = _MockIndexingBloc();
    DataRepository.instance.library = Future.value(library);
    when(() => libraryBloc.state).thenReturn(
      LibraryState.initial().copyWith(library: library),
    );
  });

  tearDown(() {
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    WindowBus.namespace = 'otzaria.window';
    MultiWindowService.debugSupportedOverride = null;
    WindowRole.isSecondary = false;
  });

  Future<Object?> sendIndexRequest(
    WidgetTester tester,
    String op, {
    Map<String, Object?> details = const {},
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<IndexingBloc>.value(value: indexingBloc),
        ],
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    return tester.runAsync(
      () async =>
          (await WindowBus.instance.onRequest!({
                'type': MultiWindowService.requestIndex,
                'op': op,
                ...details,
              }))
              as Object,
    );
  }

  testWidgets('בקשת אינדוקס מלא נכנסת מפעילה StartIndexing', (tester) async {
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpAll,
    );
    expect(accepted, isTrue);
    verify(() => indexingBloc.add(StartIndexing(library))).called(1);
  });

  testWidgets('בקשת איפוס נכנסת מפעילה ClearIndex', (tester) async {
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpClear,
    );
    expect(accepted, isTrue);
    verify(() => indexingBloc.add(any(that: isA<ClearIndex>()))).called(1);
  });

  testWidgets('בקשת איפוס ובנייה נכנסת מפעילה ResetAndIndex', (tester) async {
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpResetAndIndex,
    );
    expect(accepted, isTrue);
    verify(() => indexingBloc.add(ResetAndIndex(library))).called(1);
  });

  testWidgets('פעולה לא מוכרת נדחית', (tester) async {
    final accepted = await sendIndexRequest(tester, 'הפעלה שאינה קיימת');
    expect(accepted, isFalse);
    verifyNever(() => indexingBloc.add(any()));
  });

  // המבצע הוא המארח בלבד — חלון משני שקיבל בקשה היה שולח אותה לעצמו.
  testWidgets('חלון משני דוחה בקשת אינדוקס נכנסת', (tester) async {
    WindowRole.isSecondary = true;
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpAll,
    );
    expect(accepted, isFalse);
    verifyNever(() => indexingBloc.add(any()));
  });

  // הבעלות נקבעת ב-ProcessDuties, לא בתפקיד החלון.
  testWidgets('מי שאינו בעל התהליך דוחה בקשת אינדוקס גם כשהחלון ראשי', (
    tester,
  ) async {
    ProcessDuties.debugOverride = ProcessDuties(isProcessOwner: () => false);
    addTearDown(() => ProcessDuties.debugOverride = null);
    expect(WindowRole.isSecondary, isFalse);
    final accepted = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpAll,
    );
    expect(accepted, isFalse);
    verifyNever(() => indexingBloc.add(any()));
  });

  testWidgets('המארח ממזג בקשת הסתרה ישנה עם מצבו ומחזיר בחירה סמכותית', (
    tester,
  ) async {
    final a = TextBook(title: 'A', categoryId: 1);
    final b = TextBook(title: 'B', categoryId: 1);
    final keyA = PerBookSettings.bookKey(a);
    final keyB = PerBookSettings.bookKey(b);
    DataRepository.instance.library = Future.value(
      Library(categories: [])..books.addAll([a, b]),
    );
    await const HiddenLibraryStore().save(
      HiddenLibrarySelection(bookKeys: {keyA}),
    );

    final result = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpVisibility,
      details: {
        'fromSlot': 2,
        'operationId': '2:1',
        'bookKeys': [keyB],
        'categoryPaths': <String>[],
        'previousBookKeys': <String>[],
        'previousCategoryPaths': <String>[],
      },
    );

    expect(result, isA<Map>());
    expect((result as Map)['bookKeys'], unorderedEquals([keyA, keyB]));
    expect(const HiddenLibraryStore().load().bookKeys, {keyA, keyB});
    final event =
        verify(
              () => indexingBloc.add(
                captureAny(that: isA<ApplyHiddenIndexDelta>()),
              ),
            ).captured.single
            as ApplyHiddenIndexDelta;
    expect(event.newlyHidden, [b]);
    expect(event.newlyVisible, isEmpty);
    verify(() => libraryBloc.add(const HiddenBooksChanged())).called(1);
  });

  testWidgets('בקשות IPC עוקבות נשמרות ומאונדקסות ברצף', (tester) async {
    final a = TextBook(title: 'A', categoryId: 1);
    final b = TextBook(title: 'B', categoryId: 1);
    final keyA = PerBookSettings.bookKey(a);
    final keyB = PerBookSettings.bookKey(b);
    DataRepository.instance.library = Future.value(
      Library(categories: [])..books.addAll([a, b]),
    );
    await const HiddenLibraryStore().save(const HiddenLibrarySelection());
    await sendIndexRequest(tester, MultiWindowService.indexOpAll);
    clearInteractions(indexingBloc);

    Map<String, Object?> request(String key, int slot) => {
      'type': MultiWindowService.requestIndex,
      'op': MultiWindowService.indexOpVisibility,
      'fromSlot': slot,
      'operationId': '$slot:1',
      'bookKeys': [key],
      'categoryPaths': <String>[],
      'previousBookKeys': <String>[],
      'previousCategoryPaths': <String>[],
    };
    final first = await tester.runAsync(
      () => WindowBus.instance.onRequest!(request(keyA, 2)),
    );
    final second = await tester.runAsync(
      () => WindowBus.instance.onRequest!(request(keyB, 3)),
    );

    expect((first as Map)['bookKeys'], [keyA]);
    expect((second as Map)['bookKeys'], unorderedEquals([keyA, keyB]));
    expect(const HiddenLibraryStore().load().bookKeys, {keyA, keyB});
    final events = verify(
      () => indexingBloc.add(captureAny(that: isA<ApplyHiddenIndexDelta>())),
    ).captured.cast<ApplyHiddenIndexDelta>();
    expect(const HiddenLibraryStore().hasPendingVisibilityIndex, isTrue);
    expect(events.first.visibilityRevision, isNotNull);
    expect(
      events.last.visibilityRevision,
      greaterThan(events.first.visibilityRevision!),
    );
    expect(events.map((event) => event.newlyHidden), [
      [a],
      [b],
    ]);
  });

  testWidgets('הודעת כשל מאוחרת מסיימת בקשה גם ללא פאנל פתוח', (tester) async {
    await sendIndexRequest(tester, MultiWindowService.indexOpAll);
    MultiWindowService.trackVisibilityRequestForTesting('late-result');
    expect(MultiWindowService.pendingVisibilityRequestCountForTesting, 1);
    final delivered = await tester.runAsync(
      () => WindowBus.instance.onRequest!({
        'type': MultiWindowService.requestIndexVisibilityResult,
        'operationId': 'late-result',
        'success': false,
      }),
    );
    expect(delivered, isTrue);
    expect(MultiWindowService.pendingVisibilityRequestCountForTesting, 0);
  });

  testWidgets('כשל בכתיבת קטגוריות עדיין מסנכרן לאינדקס את הספר שנשמר', (
    tester,
  ) async {
    await Settings.init(cacheProvider: _FailingCategoryCacheProvider());
    addTearDown(
      () => Settings.init(cacheProvider: MemoryCacheProvider()),
    );
    final book = TextBook(title: 'חלקי', categoryId: 1);
    final key = PerBookSettings.bookKey(book);
    DataRepository.instance.library = Future.value(
      Library(categories: [])..books.add(book),
    );

    final result = await sendIndexRequest(
      tester,
      MultiWindowService.indexOpVisibility,
      details: {
        'fromSlot': 2,
        'operationId': '2:partial',
        'bookKeys': [key],
        'categoryPaths': ['/תורה'],
        'previousBookKeys': <String>[],
        'previousCategoryPaths': <String>[],
      },
    );

    expect((result as Map)['saved'], isFalse);
    expect(result['bookKeys'], [key]);
    expect(result['categoryPaths'], isEmpty);
    expect(const HiddenLibraryStore().load().bookKeys, {key});
    final event =
        verify(
              () => indexingBloc.add(
                captureAny(that: isA<ApplyHiddenIndexDelta>()),
              ),
            ).captured.single
            as ApplyHiddenIndexDelta;
    expect(event.newlyHidden, [book]);
    verify(() => libraryBloc.add(const HiddenBooksChanged())).called(1);
  });
}

class _FailingCategoryCacheProvider extends MemoryCacheProvider {
  @override
  Future<void> setObject<T>(String key, T? value) async {
    if (key == HiddenLibraryStore.categoryPathsSetting) {
      throw StateError('second write failed');
    }
    await super.setObject<T>(key, value);
  }
}
