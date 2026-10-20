import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/diagnostics/app_context_snapshot.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final now = DateTime(2026, 9, 17, 12);
  final redactor = AppReportRedactor(
    environment: const {'USERPROFILE': r'C:\Users\Moshe', 'USERNAME': 'Moshe'},
  );

  setUp(() => tmp = Directory.systemTemp.createTempSync('otzaria_collector_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String entry(String title, DateTime at, [String body = '']) =>
      '=== $title ${at.toIso8601String()} ===\nVersion: 1\n$body\n';

  test('אבחון: מקטע שנכשל נרשם כשגיאה ושאר המקטעים נאספים ומוסתרים', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      appInfoLoader: () async => throw StateError('library not loaded'),
      currentContext: () => {'screen': 'reading', 'tabs': 3},
      errorLogPath: p.join(tmp.path, 'missing.txt'),
      clock: () => now,
    );
    final diagnostics = await collector.collectDiagnostics();
    expect(diagnostics['appInfo'], {
      'error': 'Bad state: library not loaded',
    });
    expect(diagnostics['system'], containsPair('arch', isA<String>()));
    expect(diagnostics['context'], {'screen': 'reading', 'tabs': 3});
    expect(diagnostics['startupTimeline'], contains('lines'));
    expect(() => jsonEncode(diagnostics), returnsNormally);
  });

  test('אבחון: פרופיל המשתמש מוסתר בכל המבנה', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      appInfoLoader: () async => {
        'app': {'dataRootPath': r'C:\Users\Moshe\AppData\Roaming\otzaria'},
      },
      clock: () => now,
    );
    final diagnostics = await collector.collectDiagnostics();
    expect(
      (diagnostics['appInfo'] as Map)['app'],
      {'dataRootPath': r'%USERPROFILE%\AppData\Roaming\otzaria'},
    );
  });

  test('לוג: רק השבוע האחרון, מסודר כרונולוגית, עם לוג הסגירה', () async {
    final errors = File(p.join(tmp.path, 'errors.txt'))
      ..writeAsStringSync(
        'tail of a cut block\n'
        '${entry('Old', now.subtract(const Duration(days: 8)))}'
        '${entry('Recent A', now.subtract(const Duration(days: 2)), r'Path: C:\Users\Moshe\x')}'
        '${entry('Recent B', now.subtract(const Duration(hours: 1)))}',
      );
    final shutdown = File(p.join(tmp.path, 'shutdown.log'))
      ..writeAsStringSync(
        '${now.subtract(const Duration(days: 30)).toIso8601String()} | old\n'
        '${now.subtract(const Duration(days: 1)).toIso8601String()} | forced\n',
      );
    final collector = AppReportCollector(
      redactor: redactor,
      errorLogPath: errors.path,
      shutdownLogPath: shutdown.path,
      clock: () => now,
    );
    final log = await collector.collectErrorLog();
    expect(log, isNot(contains('Old')));
    expect(log, isNot(contains('tail of a cut block')));
    expect(log.indexOf('Recent A'), lessThan(log.indexOf('Recent B')));
    expect(log, contains(r'%USERPROFILE%\x'));
    expect(log, contains('| forced'));
    expect(log, isNot(contains('| old')));
  });

  test('לוג: קבצים חסרים מחזירים טקסט ריק', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      errorLogPath: tmp.path,
      shutdownLogPath: p.join(tmp.path, 'none.log'),
      clock: () => now,
    );
    final log = await collector.collectErrorLog();
    expect(log, isEmpty);
  });

  test('recentErrorLogExcerpt שומר את החדשות בגבול הגודל', () {
    final content = [
      for (var i = 0; i < 10; i++)
        entry('E$i', now.subtract(Duration(hours: 10 - i)), 'x' * 100),
    ].join();
    final excerpt = recentErrorLogExcerpt(
      content,
      since: now.subtract(const Duration(days: 7)),
      maxBytes: 450,
    );
    expect(excerpt, contains('E9'));
    expect(excerpt, isNot(contains('E0')));
    expect(utf8.encode(excerpt).length, lessThanOrEqualTo(450));
  });

  test('detectArch: אמולציית x64 על ARM', () {
    expect(
      AppReportCollector.detectArch(
        abi: Abi.windowsX64,
        environment: const {'PROCESSOR_IDENTIFIER': 'ARMv8 (64-bit) Family 8'},
      ),
      'x64-on-arm64',
    );
    expect(
      AppReportCollector.detectArch(
        abi: Abi.windowsX64,
        environment: const {'PROCESSOR_IDENTIFIER': 'Intel64 Family 6'},
      ),
      'x64',
    );
    expect(AppReportCollector.detectArch(abi: Abi.windowsArm64), 'arm64');
  });

  test('osVersion: הדיווח והאבחון מתקנים Windows 11 שמדווח כ-Windows 10', () {
    expect(
      AppReportCollector.osVersion(
        raw: '"Windows 10 Pro" 10.0 (Build 26100)',
        isWindows: true,
      ),
      '"Windows 11 Pro" 10.0 (Build 26100)',
    );
    expect(AppReportCollector.systemInfo()['osVersion'], displayOsVersion());
  });

  test('אבחון: אוסף שנבנה כמו בתוכנה כולל את התוספים המותקנים', () async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    // ספרייה חסרה בתיקייה הזמנית: מקטע הספרייה אינו נוגע בספרייה האמיתית.
    await Settings.setValue(
      SettingsRepository.keyLibraryPath,
      p.join(tmp.path, 'books'),
    );
    AppPaths.debugOverrideDataRootPath(tmp.path);
    addTearDown(() async {
      await PluginSystemDatabase.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
    });
    await PluginRegistryRepository().savePlugin(
      InstalledPlugin(
        pluginId: 'demo.plugin',
        name: 'Demo',
        version: '1.0.0',
        installPath: tmp.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: PluginManifest.fromJson(const {
          'id': 'demo.plugin',
          'name': 'Demo',
          'version': '1.0.0',
          'entrypoint': 'index.html',
        }),
        installedAt: now,
        updatedAt: now,
      ),
    );

    final diagnostics = await AppReportCollector(
      redactor: redactor,
      clock: () => now,
    ).collectDiagnostics();
    final plugins = (diagnostics['appInfo'] as Map)['plugins'] as Map;
    expect(plugins['installedCount'], 1);
    expect((plugins['installed'] as List).single['id'], 'demo.plugin');
  });

  group('הקשר החלון', () {
    InstalledPlugin plugin() => InstalledPlugin(
      pluginId: 'demo.plugin',
      name: 'Demo',
      version: '2.3.4',
      installPath: tmp.path,
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      manifest: PluginManifest.fromJson(const {
        'id': 'demo.plugin',
        'name': 'Demo',
        'version': '2.3.4',
        'entrypoint': 'index.html',
      }),
      installedAt: now,
      updatedAt: now,
    );

    setUp(() {
      DeveloperDiagnostics.instance.contextProvider = () => describeAppContext(
        screen: Screen.reading,
        tabs: TabsState(
          tabs: [ToolTab(toolId: 'demo.plugin', title: r'C:\Users\Moshe\Demo')],
          currentTabIndex: 0,
        ),
        pluginState: PluginSystemLoaded([plugin()]),
      );
    });
    tearDown(() => DeveloperDiagnostics.instance.contextProvider = null);

    test('נאסף מהחלון הנוכחי, כולל התוסף הפתוח, ומוסתר', () async {
      final diagnostics = await AppReportCollector(
        redactor: redactor,
        appInfoLoader: () async => {},
        clock: () => now,
      ).collectDiagnostics();
      expect(diagnostics['context'], {
        'screen': 'reading',
        'tabs': 1,
        'tabsByType': {'ToolTab': 1},
        'currentTab': 'ToolTab',
        'currentTitle': r'%USERPROFILE%\Demo',
        'plugins': [
          {
            'id': 'demo.plugin',
            'version': '2.3.4',
            'source': 'packaged',
            'enabled': true,
          },
        ],
      });
    });

    test('קריסה מהפעלה קודמת: בלי הקשר החלון הנוכחי', () async {
      final diagnostics = await AppReportCollector(
        redactor: redactor,
        appInfoLoader: () async => {},
        includeCurrentContext: false,
        clock: () => now,
      ).collectDiagnostics();
      expect(diagnostics.containsKey('context'), isFalse);
    });

    test('כרטיסיית חיפוש: השאילתה לא נכנסת לכותרת', () {
      final tab = SearchingTab(
        SearchingTab.titleForQuery('שאילתה פרטית'),
        null,
      );
      addTearDown(tab.dispose);
      final context = describeAppContext(
        screen: Screen.search,
        tabs: TabsState(tabs: [tab], currentTabIndex: 0),
        pluginState: const PluginSystemLoaded([]),
      );
      expect(context['currentTab'], 'SearchingTab');
      expect(context['currentTitle'], isNull);
    });

    Map<String, Object?> contextOf(OpenedTab tab) => describeAppContext(
      screen: Screen.reading,
      tabs: TabsState(tabs: [tab], currentTabIndex: 0),
      pluginState: PluginSystemLoaded([plugin()]),
    );

    test('חלונית מפוצלת: התוסף שבחלונית מדווח', () {
      final text = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
      addTearDown(text.dispose);
      final context = contextOf(
        CombinedTab(
          rightTab: text,
          leftTab: ToolTab(toolId: 'demo.plugin', title: 'Demo'),
        ),
      );
      expect(context['currentTab'], 'CombinedTab');
      expect(context['currentTitle'], 'משולב: בראשית | Demo');
      expect(context['plugins'], [
        {
          'id': 'demo.plugin',
          'version': '2.3.4',
          'source': 'packaged',
          'enabled': true,
        },
      ]);
    });

    test('ספר אישי: הכותרת, שהיא לרוב שם הקובץ, לא נכנסת', () {
      final pdf = PdfBookTab(
        book: PdfBook(
          title: 'מסמך פרטי',
          path: 'private.pdf',
          source: BookSource.user,
        ),
        pageNumber: 1,
      );
      final text = TextBookTab(
        book: TextBook(title: 'סיכום פרטי', source: BookSource.user),
        index: 0,
      );
      addTearDown(pdf.dispose);
      addTearDown(text.dispose);
      expect(contextOf(pdf)['currentTitle'], isNull);
      expect(contextOf(text)['currentTitle'], isNull);
      expect(
        contextOf(
          CombinedTab(
            rightTab: text,
            leftTab: ToolTab(toolId: 'demo.plugin', title: 'Demo'),
          ),
        )['currentTitle'],
        isNull,
      );
    });

    test('ספר רשמי: הכותרת נשמרת', () {
      final pdf = PdfBookTab(
        book: PdfBook(title: 'ספר רשמי', path: 'official.pdf'),
        pageNumber: 1,
      );
      addTearDown(pdf.dispose);
      expect(contextOf(pdf)['currentTitle'], 'ספר רשמי');
    });

    for (final isPdf in [false, true]) {
      for (final isPrivate in [false, true]) {
        for (final isCombined in [false, true]) {
          test(
            'מפרשים ${isPdf ? 'PDF' : 'טקסט'} '
            '${isPrivate ? 'אישי' : 'רשמי'} '
            '${isCombined ? 'בפיצול' : 'עצמאי'}: פרטיות כותרת המקור בדוח',
            () async {
              await Settings.init(cacheProvider: MemorySettingsCache());
              final source = isPrivate ? BookSource.user : BookSource.official;
              final OpenedTab commentators = isPdf
                  ? PdfCommentatorsTab(
                      sourceTab: PdfBookTab(
                        book: PdfBook(
                          title: 'כותרת המקור',
                          path: 'book.pdf',
                          source: source,
                        ),
                        pageNumber: 1,
                      ),
                      disposeSourceTabOnDispose: true,
                    )
                  : CommentatorsTab(
                      sourceTab: TextBookTab(
                        book: TextBook(title: 'כותרת המקור', source: source),
                        index: 0,
                      ),
                      disposeSourceTabOnDispose: true,
                    );
              final tab = isCombined
                  ? CombinedTab(
                      rightTab: ToolTab(toolId: 'demo.plugin', title: 'Demo'),
                      leftTab: commentators,
                    )
                  : commentators;
              addTearDown(tab.dispose);
              final diagnostics = await AppReportCollector(
                redactor: redactor,
                appInfoLoader: () async => {},
                currentContext: () => contextOf(tab),
                clock: () => now,
              ).collectDiagnostics();
              final context = diagnostics['context'] as Map;
              expect(context['currentTitle'], isPrivate ? isNull : tab.title);
              expect(
                jsonEncode(diagnostics).contains('כותרת המקור'),
                !isPrivate,
              );
            },
          );
        }
      }
    }
  });
}
