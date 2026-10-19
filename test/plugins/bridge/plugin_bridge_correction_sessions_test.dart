import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/controllable_correction_draft_repository.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _History extends Mock implements HistoryBloc {}

class _Navigation extends Mock implements NavigationBloc {}

class _Calendar extends Mock implements CalendarCubit {}

class _Workspace extends Mock implements WorkspaceBloc {}

class _Search extends Mock implements SearchRepository {}

class _Notes extends Mock implements PersonalNotesRepository {}

class _Coordinator extends Mock implements BookOpenCoordinator {}

class _Tabs extends Mock implements TabsBloc {
  late TabsState current;
  final added = <TabsEvent>[];
  @override
  TabsState get state => current;
  @override
  void add(TabsEvent event) => added.add(event);
}

class _Grants extends PluginRegistryRepository {
  _Grants(this.permissions);
  final List<String> permissions;
  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      permissions.contains(permission);
  @override
  Future<List<String>> getGrantedPermissionNames(String pluginId) async =>
      permissions;
}

class _HookedGrants extends _Grants {
  _HookedGrants(super.permissions, this.onRead);
  final void Function(int call) onRead;
  int calls = 0;

  @override
  Future<List<String>> getGrantedPermissionNames(String pluginId) async {
    onRead(++calls);
    return permissions;
  }
}

class _Reader extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _Reader(TextBook book)
    : super(
        TextBookLoaded.initial(
          book: book,
          index: 0,
          showLeftPane: false,
          splitView: false,
        ).copyWith(content: const ['בראשית א', 'שורה ב', 'שורה ג']),
      );
  void showCommentaryAtSide() =>
      emit((state as TextBookLoaded).copyWith(showSplitView: true));
  void showPageShape(bool value) =>
      emit((state as TextBookLoaded).copyWith(showPageShapeView: value));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin(String id, List<String> permissions) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: id,
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: permissions,
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: id,
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Matcher _error(String code) => throwsA(
  isA<PluginCorrectionException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

/// תוכן הסשן בלי מצב השמירה, שמתעדכן ברקע אחרי כל שינוי.
Map<String, dynamic> _content(Map<String, dynamic> snapshot) => Map.of(snapshot)
  ..remove('draft')
  ..remove('recovery');

Map<String, dynamic> _draftOf(Map<String, dynamic> snapshot) =>
    Map<String, dynamic>.from(snapshot['draft'] as Map);

Future<void> _eventually(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late String databasePath;
  late _Tabs tabs;
  late List<TextBookTab> readers;
  late PluginBridgeAdapter adapter;
  late sqlite3.Database draftDb;
  final service = PluginCorrectionSessionService.instance;
  final events = <String>[];
  final payloads = <Map<String, dynamic>>[];
  const permissions = ['reader.open', 'reader.local_edit'];
  var protectedBook = false;

  final warnings = <String>[];
  var confirmClose = true;

  PluginBridgeAdapter buildAdapter({
    String owner = 'owner',
    List<String> grants = permissions,
    PluginRegistryRepository? repository,
    Future<BookProtection> Function(Book)? bookProtectionResolver,
  }) => PluginBridgeAdapter(
    _plugin(owner, grants),
    dependencies: PluginBridgeDependencies(
      historyBloc: _History(),
      tabsBloc: tabs,
      navigationBloc: _Navigation(),
      calendarCubit: _Calendar(),
      workspaceBloc: _Workspace(),
      searchRepository: _Search(),
      personalNotesRepository: _Notes(),
      bookOpenCoordinator: _Coordinator(),
      bookProtectionResolver: bookProtectionResolver,
      themePayloadBuilder: () => {},
      showConfirmDialog: ({required title, required content}) async => true,
      showWarningDialog:
          ({required title, required content, required subtitle}) async {
            warnings.add(content);
            return confirmClose;
          },
      dispatchEventToPlugin: (pluginId, topic, payload, {instanceId}) async {
        events.add(topic);
        payloads.add(Map<String, dynamic>.from(payload));
      },
    ),
    pluginRepository: repository ?? _Grants(grants),
  );

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> args, {
    PluginBridgeAdapter? target,
  }) async => Map<String, dynamic>.from(
    await (target ?? adapter).execute('reader', action, args) as Map,
  );

  Future<Map<String, dynamic>> begin([int index = 0]) =>
      call('beginCorrectionSession', {
        'tabId': PluginCorrectionSessionService.tabIdFor(readers[index]),
      });

  Map<String, dynamic> draft(
    Map<String, dynamic> session, {
    String proposed = 'תיקון 😀',
  }) => {
    'sessionId': session['sessionId'],
    'expectedRevision': session['revision'],
    'bookUid': session['bookUid'],
    'libraryVersion': session['libraryVersion'],
    'changes': [
      {
        'sectionIndex': 0,
        'originalSourceText': 'בראשית א',
        'originalText': 'בראשית א',
        'proposedText': proposed,
      },
    ],
  };

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('correction-bridge-');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(temporary.path, 'data'));
    databasePath = SeforimFixtureDb.create(
      temporary,
      SeforimFixtureVariant.full,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      temporary.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      databasePath,
    );
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
    tabs = _Tabs();
    final book = TextBook(id: 1, title: 'בראשית');
    readers = List.generate(
      2,
      (_) => TextBookTab(book: book, index: 0, blocOverride: _Reader(book)),
    );
    tabs.current = TabsState(tabs: readers, currentTabIndex: 0);
    events.clear();
    payloads.clear();
    warnings.clear();
    confirmClose = true;
    draftDb = sqlite3.sqlite3.openInMemory();
    service.draftRepository = PluginCorrectionDraftRepository.direct(draftDb);
    adapter = buildAdapter();
  });

  tearDown(() async {
    await service.purgeOwner('owner');
    await service.purgeOwner('foreign');
    // כתיבה שכבר יצאה לפני המחיקה מסתיימת לפני סגירת החיבור.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    draftDb.close();
    for (final reader in readers) {
      await reader.bloc.close();
    }
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    await temporary.delete(recursive: true);
  });

  test(
    'סבב API מלא מחיל טיוטה רק בלשונית שלה ומשאיר את המסד והבלוק מקוריים',
    () async {
      final before = await File(databasePath).readAsBytes();
      final initial = await begin();
      expect(await begin(), initial);
      final restored = await call('restoreCorrectionDraft', draft(initial));
      expect(restored['revision'], 1);
      await expectLater(
        call('getSelection', {}),
        _error('error.unsupported_context'),
      );
      for (final layer in ['rendered', 'both']) {
        await expectLater(
          call('getSectionTextMap', {
            'bookId': 'בראשית',
            'bookUid': restored['bookUid'],
            'sectionIndex': 0,
            'layer': layer,
          }),
          _error('error.unsupported_context'),
        );
      }
      final map = await call('getSectionTextMap', {
        'bookId': 'בראשית',
        'bookUid': restored['bookUid'],
        'sectionIndex': 0,
        'layer': 'source',
      });
      expect(map['sourceText'], 'בראשית א');
      final current = await call('getCorrectionSession', {
        'sessionId': initial['sessionId'],
      });
      expect(_content(current), _content(restored));
      expect(_draftOf(current)['persisted'], isTrue);
      expect(_draftOf(current)['version'], isA<int>());
      expect(
        PluginCorrectionSessionService.instance.displayText(
          initial['tabId'],
          0,
          'בראשית א',
        ),
        'תיקון 😀',
      );
      // אותו תוסף ואותו ספר בלשונית נוספת — טיוטה אחת לכל תוסף+ספר.
      await expectLater(begin(1), _error('error.correction_busy'));
      expect(
        PluginCorrectionSessionService.instance.displayText(
          PluginCorrectionSessionService.tabIdFor(readers[1]),
          0,
          'בראשית א',
        ),
        'בראשית א',
      );
      expect(
        (readers.first.bloc.state as TextBookLoaded).content.first,
        'בראשית א',
      );
      final db = sqlite3.sqlite3.open(
        databasePath,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        expect(
          db
              .select(
                'SELECT content FROM line WHERE bookId = 1 AND lineIndex = 0',
              )
              .single['content'],
          'בראשית א',
        );
      } finally {
        db.close();
      }
      expect(await File(databasePath).readAsBytes(), before);
      final reset = await call('resetCorrection', {
        'sessionId': initial['sessionId'],
        'expectedRevision': 1,
        'sectionIndex': 0,
      });
      expect(reset['changes'], isEmpty);
      expect(reset['revision'], 2);
      await call('getCorrectionSession', {'sessionId': initial['sessionId']});
      final ended = await call('endCorrectionSession', {
        'sessionId': initial['sessionId'],
        'expectedRevision': 2,
      });
      expect(_content(ended), _content(reset));
      expect(_draftOf(ended)['persisted'], isTrue);
      await expectLater(
        call('getCorrectionSession', {'sessionId': initial['sessionId']}),
        _error('error.not_found'),
      );
      expect(events, [
        'reader.correctionSessionChanged',
        'reader.correctionSessionChanged',
        'reader.correctionSessionEnded',
      ]);
    },
  );

  test('tabId יציב וייחודי גם לשתי לשוניות אותו ספר', () async {
    final first = await call('getCurrentState', {});
    final second = await call('getCurrentState', {});
    expect(second, first);
    final openTabs = first['openTabs'] as List;
    expect(openTabs[0]['tabId'], isNot(openTabs[1]['tabId']));
    expect(first['currentTabId'], openTabs[0]['tabId']);
    expect((await begin())['tabId'], openTabs[0]['tabId']);
    tabs.current = TabsState(tabs: readers, currentTabIndex: 1);
    final switched = await call('getCurrentState', {});
    expect(switched['currentTabId'], openTabs[1]['tabId']);
    tabs.current = TabsState(tabs: [readers[1]], currentTabIndex: 0);
    final remaining = await call('getCurrentState', {});
    expect(remaining['currentTabId'], openTabs[1]['tabId']);
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': openTabs[0]['tabId'],
      }),
      _error('error.not_found'),
    );
  });

  test('מצב הקורא חושף רק סשן קיים של בעליו גם למופע חדש', () async {
    final initial = await call('getCurrentState', {});
    expect(initial['currentCorrectionSessionId'], isNull);
    expect(
      (initial['openTabs'] as List).map((tab) => tab['correctionSessionId']),
      everyElement(isNull),
    );
    final session = await begin();
    final foreground = buildAdapter();
    final owned = await call('getCurrentState', {}, target: foreground);
    expect(owned['currentCorrectionSessionId'], session['sessionId']);
    expect(
      (owned['openTabs'] as List)[0]['correctionSessionId'],
      session['sessionId'],
    );
    expect((owned['openTabs'] as List)[1]['correctionSessionId'], isNull);
    expect(
      await call('getCorrectionSession', {
        'sessionId': owned['currentCorrectionSessionId'],
      }, target: foreground),
      Map.of(session)..remove('recovery'),
    );
    final foreign = buildAdapter(owner: 'foreign');
    final hidden = await call('getCurrentState', {}, target: foreign);
    expect(hidden['currentCorrectionSessionId'], isNull);
    expect(
      (hidden['openTabs'] as List).map((tab) => tab['correctionSessionId']),
      everyElement(isNull),
    );
    tabs.current = TabsState(tabs: readers, currentTabIndex: 1);
    expect(
      (await call('getCurrentState', {}))['currentCorrectionSessionId'],
      isNull,
    );
    await call('endCorrectionSession', {
      'sessionId': session['sessionId'],
      'expectedRevision': 0,
    });
    final ended = await call('getCurrentState', {});
    expect(
      (ended['openTabs'] as List).map((tab) => tab['correctionSessionId']),
      everyElement(isNull),
    );
    tabs.current = const TabsState(tabs: [], currentTabIndex: 0);
    expect(
      (await call('getCurrentState', {}))['currentCorrectionSessionId'],
      isNull,
    );
  });

  test('הסרת הבעלים באמצע begin אינה משאירה סשן יתום', () async {
    final racing = buildAdapter(
      repository: _HookedGrants(permissions, (call) {
        if (call == 2) {
          PluginCorrectionSessionService.instance.removeOwner('owner');
        }
      }),
    );
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': PluginCorrectionSessionService.tabIdFor(readers.first),
      }, target: racing),
      _error('error.permission_denied'),
    );
    expect(
      PluginCorrectionSessionService.instance.hasSessionForTab(
        PluginCorrectionSessionService.tabIdFor(readers.first),
      ),
      isFalse,
    );
  });

  test('לשונית שנפתחה לפי כותרת משתמשת ב-id שנפתר ב-state של הקורא', () async {
    final titled = TextBookTab(
      book: TextBook(title: 'בראשית'),
      index: 0,
      blocOverride: _Reader(TextBook(id: 1, title: 'בראשית')),
    );
    addTearDown(titled.bloc.close);
    tabs.current = TabsState(tabs: [titled], currentTabIndex: 0);
    final session = await call('beginCorrectionSession', {
      'tabId': PluginCorrectionSessionService.tabIdFor(titled),
    });
    expect(
      session['bookUid'],
      PluginBookIdentity.uidOf((titled.bloc.state as TextBookLoaded).book),
    );
    final restored = await call('restoreCorrectionDraft', draft(session));
    expect((restored['changes'] as List).single['proposedText'], 'תיקון 😀');
  });

  test('צורת הדף משאירה את הסשן, חוסמת שינוי ומאפשרת קריאה וסיום', () async {
    final session = await begin();
    final restored = await call('restoreCorrectionDraft', draft(session));
    (readers.first.bloc as _Reader).showPageShape(true);
    await expectLater(
      call('restoreCorrectionDraft', draft(restored, proposed: 'אחר')),
      _error('error.unsupported_context'),
    );
    await expectLater(
      call('resetCorrection', {
        'sessionId': session['sessionId'],
        'expectedRevision': restored['revision'],
        'sectionIndex': 0,
      }),
      _error('error.unsupported_context'),
    );
    final current = await call('getCorrectionSession', {
      'sessionId': session['sessionId'],
    });
    expect(_content(current), _content(restored));
    try {
      await call('getSelection', {});
    } on Object catch (error) {
      expect(
        error.toString(),
        isNot(contains('בחירה בנוסח מתוקן')),
        reason: 'בצורת הדף מוצג הנוסח הרשמי, ולכן הבחירה אינה חסומה',
      );
    }
    (readers.first.bloc as _Reader).showPageShape(false);
    await expectLater(
      call('getSelection', {}),
      _error('error.unsupported_context'),
    );
    final ended = await call('endCorrectionSession', {
      'sessionId': session['sessionId'],
      'expectedRevision': restored['revision'],
    });
    expect(_content(ended), _content(restored));
    expect(_draftOf(ended), _draftOf(current));
  });

  test('מפרשים בצד מאפשרים סשן ותיקון בטקסט הראשי בלבד', () async {
    (readers.first.bloc as _Reader).showCommentaryAtSide();
    final session = await begin();
    expect((session['capabilities'] as Map)['splitView'], isTrue);
    final restored = await call('restoreCorrectionDraft', draft(session));
    expect((restored['changes'] as List).single['proposedText'], 'תיקון 😀');
    expect(
      (readers.first.bloc.state as TextBookLoaded).content.first,
      'בראשית א',
    );
    expect(
      PluginCorrectionSessionService.instance.hasSessionForTab(
        PluginCorrectionSessionService.tabIdFor(readers[1]),
      ),
      isFalse,
    );
  });

  test('הרשאה חסרה ובעלות זרה אינן מאפשרות גישה לסשן', () async {
    final denied = buildAdapter(grants: const ['reader.open']);
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': PluginCorrectionSessionService.tabIdFor(readers.first),
      }, target: denied),
      _error('error.permission_denied'),
    );
    final session = await begin();
    await expectLater(
      call('getCorrectionSession', {
        'sessionId': session['sessionId'],
      }, target: denied),
      _error('error.permission_denied'),
    );
    final foreign = buildAdapter(owner: 'foreign');
    await expectLater(
      call('getCorrectionSession', {
        'sessionId': session['sessionId'],
      }, target: foreign),
      _error('error.not_found'),
    );
    await expectLater(
      call('restoreCorrectionDraft', draft(session), target: foreign),
      _error('error.not_found'),
    );
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': session['tabId'],
      }, target: foreign),
      _error('error.correction_busy'),
    );
  });

  test('ספר מוגן אינו פותח סשן ואינו מחזיר snapshot תיקון', () async {
    final tabId = PluginCorrectionSessionService.tabIdFor(readers.first);
    final protectedAdapter = buildAdapter(
      bookProtectionResolver: (_) async =>
          protectedBook ? const BookProtection(level: 2) : BookProtection.none,
    );
    protectedBook = true;
    await expectLater(
      call('beginCorrectionSession', {
        'tabId': tabId,
      }, target: protectedAdapter),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('error.forbidden'),
        ),
      ),
    );
    expect(service.hasSessionForTab(tabId), isFalse);

    protectedBook = false;
    final session = await begin();
    protectedBook = true;
    await expectLater(
      call(
        'getCorrectionSession',
        {'sessionId': session['sessionId']},
        target: protectedAdapter,
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('error.forbidden'),
        ),
      ),
    );
  });

  test('סגירת טאב בזמן בדיקת הגנת הספר אינה משאירה סשן יתום', () async {
    final tabId = PluginCorrectionSessionService.tabIdFor(readers.first);
    final entered = Completer<void>();
    final release = Completer<void>();
    var protectionCalls = 0;
    final closingAdapter = buildAdapter(
      bookProtectionResolver: (_) async {
        if (++protectionCalls == 2) {
          entered.complete();
          await release.future;
        }
        return BookProtection.none;
      },
    );
    final pending = call(
      'beginCorrectionSession',
      {'tabId': tabId},
      target: closingAdapter,
    );
    await entered.future;
    tabs.current = TabsState(
      tabs: readers.skip(1).toList(),
      currentTabIndex: 0,
    );
    release.complete();

    await expectLater(pending, _error('error.not_found'));
    expect(service.hasSessionForTab(tabId), isFalse);
  });

  test('פרמטרים פגומים וטיוטה ממקור אחר אינם משנים סשן', () async {
    for (final args in <Map<String, dynamic>>[
      {},
      {'tabId': 42},
      {'tabId': ''},
      {'tabId': 'missing', 'extra': true},
    ]) {
      await expectLater(
        call('beginCorrectionSession', args),
        _error('error.invalid_params'),
      );
    }
    await expectLater(
      call('beginCorrectionSession', {'tabId': 'missing'}),
      _error('error.not_found'),
    );
    final session = await begin();
    for (final args in <Map<String, dynamic>>[
      {...draft(session), 'expectedRevision': '0'},
      {...draft(session), 'expectedRevision': -1},
      {...draft(session), 'expectedRevision': 0.5},
      {...draft(session), 'changes': {}},
      {...draft(session), 'extra': true},
    ]) {
      await expectLater(
        call('restoreCorrectionDraft', args),
        _error('error.invalid_params'),
      );
    }
    await expectLater(
      call('restoreCorrectionDraft', {...draft(session), 'bookUid': 'id:999'}),
      _error('error.source_changed'),
    );
    await expectLater(
      call('restoreCorrectionDraft', draft(session, proposed: '<b>תיקון</b>')),
      _error('error.unsupported_context'),
    );
    expect(
      await call('getCorrectionSession', {'sessionId': session['sessionId']}),
      Map.of(session)..remove('recovery'),
    );
    expect(events, isEmpty);
  });

  test('גרסה לא ידועה אינה מאפשרת לפתוח סשן', () async {
    final db = sqlite3.sqlite3.open(databasePath);
    try {
      db.execute("DELETE FROM schema_meta WHERE key = 'db_version'");
    } finally {
      db.close();
    }
    await expectLater(begin(), _error('error.source_changed'));
  });

  test('גשר RPC אוכף גם הצהרה במניפסט וגם אישור להרשאה', () async {
    for (final declared in [false, true]) {
      final handler = PluginBridgeHandler(
        _plugin('owner', declared ? permissions : const ['reader.open']),
        adapter: adapter,
        registry: _Grants(declared ? const ['reader.open'] : permissions),
      );
      final response =
          await handler.handleRpcForTesting([
                {
                  'method': 'reader.beginCorrectionSession',
                  'payload': {
                    'tabId': PluginCorrectionSessionService.tabIdFor(
                      readers.first,
                    ),
                  },
                },
              ])
              as Map;
      expect(response['success'], isFalse);
      expect(response['error']['code'], 'permission_denied');
    }
    final handler = PluginBridgeHandler(
      _plugin('owner', permissions),
      adapter: adapter,
      registry: _Grants(permissions),
    );
    final response =
        await handler.handleRpcForTesting([
              {
                'method': 'reader.beginCorrectionSession',
                'payload': {
                  'tabId': PluginCorrectionSessionService.tabIdFor(
                    readers.first,
                  ),
                },
              },
            ])
            as Map;
    expect(response['success'], isTrue);
  });

  test('שינוי גרסה עם טקסט זהה דוחה גם ניקוי טיוטה אטומי', () async {
    final initial = await begin();
    final restored = await call('restoreCorrectionDraft', draft(initial));
    final persisted = await call('getCorrectionSession', {
      'sessionId': restored['sessionId'],
    });
    events.clear();
    final db = sqlite3.sqlite3.open(databasePath);
    try {
      db.execute("UPDATE schema_meta SET value = '2' WHERE key = 'db_version'");
    } finally {
      db.close();
    }
    await expectLater(
      call('restoreCorrectionDraft', draft(restored)),
      _error('error.source_changed'),
    );
    await expectLater(
      call('restoreCorrectionDraft', {...draft(restored), 'changes': []}),
      _error('error.source_changed'),
    );
    expect(
      await call('getCorrectionSession', {'sessionId': restored['sessionId']}),
      persisted,
    );
    expect(_content(persisted), _content(restored));
    expect(events, isEmpty);
  });

  group('חסמי קריאה על נוסח מתוקן', () {
    Map<String, dynamic> section(String layer, {bool withUid = true}) => {
      'bookId': 'בראשית',
      if (withUid) 'bookUid': 'id:1',
      'sectionIndex': 0,
      'layer': layer,
    };

    test(
      'findTextOccurrences בשכבת rendered חסום, ושכבת המקור פתוחה',
      () async {
        final session = await begin();
        Map<String, dynamic> find(String layer) => {
          'bookId': 'בראשית',
          'bookUid': session['bookUid'],
          'sectionIndex': 0,
          'query': 'בראשית',
          'layer': layer,
        };
        await expectLater(
          call('findTextOccurrences', find('rendered')),
          _error('error.unsupported_context'),
        );
        final source = await call('findTextOccurrences', find('source'));
        expect(source, isNotEmpty);
      },
    );

    test('מפת מקור חסומה גם בשכבת source וגם בלי bookUid', () async {
      await begin();
      await expectLater(
        call('getSectionTextMap', {
          ...section('source'),
          'includeSourceMap': true,
        }),
        _error('error.unsupported_context'),
      );
      await expectLater(
        call('getSectionTextMap', section('rendered', withUid: false)),
        _error('error.unsupported_context'),
      );
    });

    test('רווחים סביב bookUid אינם עוקפים את החסם', () async {
      final session = await begin();
      await expectLater(
        call('getSectionTextMap', {
          ...section('rendered'),
          'bookUid': '  ${session['bookUid']}	',
        }),
        _error('error.unsupported_context'),
      );
    });

    test('ספר אחר שאין עליו סשן אינו נחסם', () async {
      await begin();
      final other = await call('getSectionTextMap', {
        'bookId': 'ספר אחר',
        'sectionIndex': 0,
        'layer': 'source',
      }).then<Object?>((value) => value, onError: (Object error) => error);
      expect(
        other.toString(),
        isNot(contains('מפת הנוסח המתוקן')),
        reason: 'החסם חל רק על ספר שיש עליו סשן',
      );
    });
  });

  group('ולידציית פרמטרים בכל הפעולות', () {
    test('מפתחות נוספים או חסרים נדחים לפני כל גישה לסשן', () async {
      final session = await begin();
      final id = session['sessionId'];
      final bad = <(String, Map<String, dynamic>)>[
        ('getCorrectionSession', {'sessionId': id, 'extra': 1}),
        ('getCorrectionSession', {'sessionId': 5}),
        ('getCorrectionSession', {}),
        ('endCorrectionSession', {'sessionId': id}),
        ('endCorrectionSession', {'sessionId': id, 'expectedRevision': '0'}),
        (
          'endCorrectionSession',
          {
            'sessionId': id,
            'expectedRevision': 0,
            'extra': 1,
          },
        ),
        ('resetCorrection', {'sessionId': id, 'expectedRevision': 0}),
        (
          'resetCorrection',
          {
            'sessionId': id,
            'expectedRevision': 0,
            'sectionIndex': '0',
          },
        ),
        (
          'resetCorrection',
          {
            'sessionId': id,
            'expectedRevision': 0,
            'sectionIndex': -1,
          },
        ),
        (
          'restoreCorrectionDraft',
          {
            ...draft(session),
            'bookUid': 7,
          },
        ),
        (
          'restoreCorrectionDraft',
          {
            ...draft(session),
            'libraryVersion': null,
          },
        ),
        (
          'restoreCorrectionDraft',
          {
            'sessionId': id,
            'expectedRevision': 0,
            'bookUid': session['bookUid'],
            'libraryVersion': session['libraryVersion'],
          },
        ),
      ];
      for (final (action, args) in bad) {
        await expectLater(
          call(action, args),
          _error('error.invalid_params'),
          reason: '$action $args',
        );
      }
      expect(
        (await call('getCorrectionSession', {'sessionId': id}))['revision'],
        0,
      );
    });
  });

  group('תוכן האירועים', () {
    test(
      'שינוי, איפוס וסיום נושאים sessionId, revision, סיבה ותמונה',
      () async {
        final session = await begin();
        final id = session['sessionId'];
        final restored = await call('restoreCorrectionDraft', draft(session));
        await call('getCorrectionSession', {'sessionId': id});
        await call('resetCorrection', {
          'sessionId': id,
          'expectedRevision': restored['revision'],
          'sectionIndex': 0,
        });
        await call('getCorrectionSession', {'sessionId': id});
        await call('endCorrectionSession', {
          'sessionId': id,
          'expectedRevision': 2,
        });
        expect(payloads, hasLength(3));
        expect(payloads[0], {
          'sessionId': id,
          'revision': 1,
          'sectionIndices': [0],
        });
        expect(payloads[1], {
          'sessionId': id,
          'revision': 2,
          'sectionIndices': [0],
        });
        expect(
          payloads[2].keys,
          unorderedEquals(['sessionId', 'reason', 'snapshot']),
        );
        expect(payloads[2]['sessionId'], id);
        expect(payloads[2]['reason'], 'explicit');
        final snapshot = Map<String, dynamic>.from(payloads[2]['snapshot']);
        expect(snapshot['revision'], 2);
        expect(_draftOf(snapshot)['persisted'], isTrue);
      },
    );

    test('שינויים רצופים מאוחדים לאירוע אחד עם כל הפסקאות', () async {
      final window = PluginCorrectionSessionService.eventWindow;
      PluginCorrectionSessionService.eventWindow = const Duration(minutes: 1);
      addTearDown(() => PluginCorrectionSessionService.eventWindow = window);
      final session = await begin();
      final id = session['sessionId'];
      final restored = await call('restoreCorrectionDraft', {
        ...draft(session),
        'changes': [
          for (final (index, text) in [(0, 'בראשית א'), (1, 'שורה ב')])
            {
              'sectionIndex': index,
              'originalSourceText': text,
              'originalText': text,
              'proposedText': '$text מתוקן',
            },
        ],
      });
      await call('resetCorrection', {
        'sessionId': id,
        'expectedRevision': restored['revision'],
        'sectionIndex': 1,
      });
      expect(events, isEmpty, reason: 'האירוע ממתין לחלון הקצב');
      await call('getCorrectionSession', {'sessionId': id});
      expect(payloads.single, {
        'sessionId': id,
        'revision': 2,
        'sectionIndices': [0, 1],
      });
    });

    test(
      'ביטול הרשאת התיקון המקומי מסיים את הסשן עם plugin_unavailable',
      () async {
        await begin();
        payloads.clear();
        PluginCorrectionSessionService.instance.removeOwner('owner');
        await _eventually(() => payloads.isNotEmpty);
        expect(payloads.single['reason'], 'plugin_unavailable');
      },
    );
  });

  group('טיוטות התאוששות', () {
    Future<Map<String, dynamic>> edited([String proposed = 'תיקון 😀']) async {
      final session = await begin();
      await call('restoreCorrectionDraft', draft(session, proposed: proposed));
      return call('getCorrectionSession', {'sessionId': session['sessionId']});
    }

    Future<Map<String, dynamic>> end(Map<String, dynamic> snapshot) =>
        call('endCorrectionSession', {
          'sessionId': snapshot['sessionId'],
          'expectedRevision': snapshot['revision'],
        });

    Future<Map<String, dynamic>> ack(
      Map<String, dynamic> snapshot, {
      PluginBridgeAdapter? target,
      int? version,
    }) => call('acknowledgeCorrectionDraft', {
      'draftId': _draftOf(snapshot)['draftId'],
      'version': version ?? _draftOf(snapshot)['version'],
    }, target: target);

    test('begin מחזיר טיוטה ריקה שמורה ו-recovery null', () async {
      final session = await begin();
      expect(session['recovery'], isNull);
      expect(session.containsKey('recovery'), isTrue);
      final saved = _draftOf(session);
      expect(
        saved['draftId'],
        isA<String>().having((v) => v, 'id', isNotEmpty),
      );
      expect(saved, {
        'draftId': saved['draftId'],
        'version': null,
        'persisted': true,
        'pending': false,
        'displaced': false,
        'error': null,
        'conflicts': isEmpty,
      });
      expect((await call('listCorrectionDrafts', {}))['drafts'], isEmpty);
    });

    test('עריכה שלא אושרה משוחזרת ב-begin הבא אחרי סיום', () async {
      final current = await edited();
      final ended = await end(current);
      expect(_draftOf(ended)['version'], _draftOf(current)['version']);
      expect(_draftOf(ended)['persisted'], isTrue);
      events.clear();
      payloads.clear();
      final reopened = await begin(1);
      expect(reopened['sessionId'], isNot(current['sessionId']));
      expect(reopened['recovery'], {
        'draftId': _draftOf(current)['draftId'],
        'fromVersion': _draftOf(current)['version'],
        'restoredSectionIndices': [0],
        'conflicts': isEmpty,
      });
      expect(reopened['revision'], 1);
      expect(_content(reopened)['changes'], current['changes']);
      expect(_draftOf(reopened)['draftId'], _draftOf(current)['draftId']);
      expect(_draftOf(reopened)['persisted'], isTrue);
      expect(
        _draftOf(reopened)['version'],
        greaterThan(_draftOf(current)['version'] as int),
      );
      expect(
        service.displayText(reopened['tabId'], 0, 'בראשית א'),
        'תיקון 😀',
      );
      expect(events, isEmpty, reason: 'השחזור אינו נחשב שינוי של התוסף');
    });

    test('תיקון שמקורו השתנה חוזר כהתנגשות עד לאישור', () async {
      final current = await edited();
      await end(current);
      final db = sqlite3.sqlite3.open(databasePath);
      try {
        db.execute(
          "UPDATE line SET content = 'בראשית שונה' "
          'WHERE bookId = 1 AND lineIndex = 0',
        );
      } finally {
        db.close();
      }
      final reopened = await begin();
      final recovery = Map<String, dynamic>.from(reopened['recovery'] as Map);
      expect(recovery['restoredSectionIndices'], isEmpty);
      final conflict = Map<String, dynamic>.from(
        (recovery['conflicts'] as List).single as Map,
      );
      expect(conflict, {
        ...(current['changes'] as List).single as Map,
        'reason': 'source_changed',
      });
      expect(reopened['changes'], isEmpty);
      expect(_draftOf(reopened)['conflicts'], [conflict]);
      final again = await call('getCorrectionSession', {
        'sessionId': reopened['sessionId'],
      });
      expect(_draftOf(again)['conflicts'], [conflict]);
      expect(
        (await call('getCorrectionDraft', {
          'draftId': _draftOf(again)['draftId'],
        }))['conflicts'],
        [conflict],
      );
      await ack(again);
      final cleared = await call('getCorrectionSession', {
        'sessionId': reopened['sessionId'],
      });
      expect(_draftOf(cleared)['conflicts'], isEmpty);
    });

    test(
      'אישור אחרי סיום מוחק את הטיוטה, וחזרה עליו מסומנת duplicate',
      () async {
        final ended = await end(await edited());
        final saved = _draftOf(ended);
        expect(await ack(ended), {
          'draftId': saved['draftId'],
          'version': saved['version'],
          'acknowledged': true,
          'duplicate': false,
        });
        expect(await ack(ended), {
          'draftId': saved['draftId'],
          'version': saved['version'],
          'acknowledged': true,
          'duplicate': true,
        });
        expect((await call('listCorrectionDrafts', {}))['drafts'], isEmpty);
        await expectLater(
          call('getCorrectionDraft', {'draftId': saved['draftId']}),
          _error('error.not_found'),
        );
        final reopened = await begin();
        expect(reopened['recovery'], isNull);
        expect(reopened['changes'], isEmpty);
      },
    );

    test('אישור גרסה ישנה נדחה; אישור בסשן פעיל אינו עוצר עריכה', () async {
      final first = await edited('גרסה א');
      final second = await call('getCorrectionSession', {
        'sessionId': (await call(
          'restoreCorrectionDraft',
          draft(first, proposed: 'גרסה ב'),
        ))['sessionId'],
      });
      final older = _draftOf(first)['version'] as int;
      final newer = _draftOf(second)['version'] as int;
      expect(newer, greaterThan(older));
      await expectLater(
        ack(second, version: older),
        _error('error.revision_conflict'),
      );
      expect((await ack(second))['duplicate'], isFalse);
      expect((await call('listCorrectionDrafts', {}))['drafts'], isEmpty);
      final still = await call('getCorrectionSession', {
        'sessionId': second['sessionId'],
      });
      expect(still['changes'], second['changes']);
      final third = await call('getCorrectionSession', {
        'sessionId': (await call(
          'restoreCorrectionDraft',
          draft(still, proposed: 'גרסה ג'),
        ))['sessionId'],
      });
      expect(_draftOf(third)['version'], greaterThan(newer));
      final listed = (await call('listCorrectionDrafts', {}))['drafts'] as List;
      expect((listed.single as Map)['version'], _draftOf(third)['version']);
    });

    test('list ו-get מחזירים את טיוטות התוסף עם מטא-דאטה ותוכן', () async {
      final current = await edited();
      final saved = _draftOf(current);
      final listed = await call('listCorrectionDrafts', {});
      expect(listed.keys, ['drafts']);
      expect(listed['drafts'], [
        {
          'draftId': saved['draftId'],
          'bookId': 'בראשית',
          'bookUid': current['bookUid'],
          'bookSource': PluginBookIdentity.sourceOf(
            (readers.first.bloc.state as TextBookLoaded).book,
          ),
          'libraryVersion': current['libraryVersion'],
          'version': saved['version'],
          'updatedAt': isA<String>(),
          'active': true,
          'changeCount': 1,
          'conflictCount': 0,
        },
      ]);
      final full = await call('getCorrectionDraft', {
        'draftId': saved['draftId'],
      });
      expect(full['version'], saved['version']);
      expect(full['active'], isTrue);
      expect(full['changes'], current['changes']);
      expect(full['conflicts'], isEmpty);
      await end(current);
      final after = await call('getCorrectionDraft', {
        'draftId': saved['draftId'],
      });
      expect(after['active'], isFalse);
      expect(after['changes'], current['changes']);
    });

    test('תוסף אחר אינו רואה ואינו מאשר טיוטה שאינה שלו', () async {
      final ended = await end(await edited());
      final foreign = buildAdapter(owner: 'foreign');
      await expectLater(
        ack(ended, target: foreign),
        _error('error.not_found'),
      );
      await expectLater(
        call('getCorrectionDraft', {
          'draftId': _draftOf(ended)['draftId'],
        }, target: foreign),
        _error('error.not_found'),
      );
      expect(
        (await call('listCorrectionDrafts', {}, target: foreign))['drafts'],
        isEmpty,
      );
      expect((await call('listCorrectionDrafts', {}))['drafts'], hasLength(1));
    });

    test('פרמטרים פגומים נדחים', () async {
      final ended = await end(await edited());
      final id = _draftOf(ended)['draftId'];
      final version = _draftOf(ended)['version'];
      final bad = <(String, Map<String, dynamic>)>[
        ('acknowledgeCorrectionDraft', {}),
        ('acknowledgeCorrectionDraft', {'draftId': id}),
        ('acknowledgeCorrectionDraft', {'version': version}),
        ('acknowledgeCorrectionDraft', {'draftId': '', 'version': version}),
        ('acknowledgeCorrectionDraft', {'draftId': 5, 'version': version}),
        ('acknowledgeCorrectionDraft', {'draftId': id, 'version': '$version'}),
        ('acknowledgeCorrectionDraft', {'draftId': id, 'version': -1}),
        ('acknowledgeCorrectionDraft', {'draftId': id, 'version': 1.5}),
        (
          'acknowledgeCorrectionDraft',
          {'draftId': id, 'version': version, 'extra': 1},
        ),
        ('listCorrectionDrafts', {'extra': 1}),
        ('getCorrectionDraft', {}),
        ('getCorrectionDraft', {'draftId': ''}),
        ('getCorrectionDraft', {'draftId': 5}),
        ('getCorrectionDraft', {'draftId': id, 'version': version}),
      ];
      for (final (action, args) in bad) {
        await expectLater(
          call(action, args),
          _error('error.invalid_params'),
          reason: '$action $args',
        );
      }
      expect((await call('listCorrectionDrafts', {}))['drafts'], hasLength(1));
    });

    test('בלי הרשאת תיקון מקומי אין גישה לטיוטות', () async {
      final ended = await end(await edited());
      final denied = buildAdapter(grants: const ['reader.open']);
      for (final (action, args) in <(String, Map<String, dynamic>)>[
        ('listCorrectionDrafts', {}),
        ('getCorrectionDraft', {'draftId': _draftOf(ended)['draftId']}),
        (
          'acknowledgeCorrectionDraft',
          {
            'draftId': _draftOf(ended)['draftId'],
            'version': _draftOf(ended)['version'],
          },
        ),
      ]) {
        await expectLater(
          call(action, args, target: denied),
          _error('error.permission_denied'),
          reason: action,
        );
      }
      for (final method in const [
        'reader.listCorrectionDrafts',
        'reader.getCorrectionDraft',
        'reader.acknowledgeCorrectionDraft',
      ]) {
        final handler = PluginBridgeHandler(
          _plugin('owner', const ['reader.open']),
          adapter: adapter,
          registry: _Grants(permissions),
        );
        final response =
            await handler.handleRpcForTesting([
                  {'method': method, 'payload': <String, dynamic>{}},
                ])
                as Map;
        expect(response['success'], isFalse, reason: method);
        expect(response['error']['code'], 'permission_denied', reason: method);
      }
      expect((await call('listCorrectionDrafts', {}))['drafts'], hasLength(1));
    });
  });

  group('reader.closeTab על לשונית קורא עם תיקונים', () {
    late ControllableCorrectionDraftRepository drafts;

    setUp(() {
      drafts = ControllableCorrectionDraftRepository(
        PluginCorrectionDraftRepository.direct(draftDb),
      );
      service.draftRepository = drafts;
      addTearDown(() {
        drafts.failWrites = false;
        if (drafts.gate case final gate? when !gate.isCompleted) {
          gate.complete();
        }
      });
    });

    Future<Object?> closeFirst() =>
        adapter.execute('reader', 'closeTab', {'index': 0});

    test('טיוטה שנשמרה נסגרת בלי אזהרה', () async {
      final session = await begin();
      await call('restoreCorrectionDraft', draft(session));
      expect(await closeFirst(), isTrue);
      expect(warnings, isEmpty);
      expect(tabs.added.single, isA<RemoveTab>());
    });

    test('כתיבה ממתינה מושלמת לפני הסגירה, בלי אזהרת אובדן', () async {
      final session = await begin();
      drafts.gate = Completer<void>();
      await call('restoreCorrectionDraft', draft(session));
      final closing = closeFirst();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tabs.added, isEmpty, reason: 'הסגירה ממתינה לשמירה');
      drafts.gate!.complete();
      expect(await closing, isTrue);
      expect(warnings, isEmpty);
      expect(tabs.added.single, isA<RemoveTab>());
      final stored = await service.getDraft(
        'owner',
        session['draft']['draftId'],
      );
      expect((stored['changes'] as List).single['proposedText'], 'תיקון 😀');
    });

    test(
      'כתיבה שנכשלת: אזהרה; ביטול משאיר את הלשונית, הסשן והשינויים',
      () async {
        final session = await begin();
        drafts.failWrites = true;
        final edited = await call('restoreCorrectionDraft', draft(session));
        confirmClose = false;

        expect(await closeFirst(), isFalse);
        expect(warnings.single, contains(unsavedCorrectionsMessage('owner')));
        expect(tabs.added, isEmpty);
        final after = await call('getCorrectionSession', {
          'sessionId': session['sessionId'],
        });
        expect(after['revision'], edited['revision']);
        expect(_content(after), _content(edited));
        expect(after['draft']['persisted'], isFalse);

        // אחרי תיקון התקלה הסגירה עוברת בלי אזהרה.
        drafts.failWrites = false;
        expect(await closeFirst(), isTrue);
        expect(warnings, hasLength(1));
        expect(tabs.added.single, isA<RemoveTab>());
      },
    );

    test('כתיבה שנכשלת: אישור סוגר, והמצב נשאר באזהרת היציאה', () async {
      final session = await begin();
      drafts.failWrites = true;
      await call('restoreCorrectionDraft', draft(session));
      expect(await closeFirst(), isTrue);
      expect(warnings, hasLength(1));
      expect(tabs.added.single, isA<RemoveTab>());
      // ה-RemoveTab מגיע ל-bloc אמיתי שמשחרר את הלשונית; כאן מדמים את ה-dispose.
      service.removeTab(PluginCorrectionSessionService.tabIdFor(readers[0]));
      expect(
        [for (final state in await service.unsavedStates()) state.ownerName],
        ['owner'],
      );
    });
  });
}
