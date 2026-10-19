import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_paragraph.dart';
import 'package:otzaria/plugins/view/plugin_correction_session_banner.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

typedef _Banner = PluginCorrectionSessionBanner;

/// מצב תצוגה נשלט, בלי מאגר טיוטות.
class _FakeService extends PluginCorrectionSessionService {
  String? owner = 'בודק';
  PluginCorrectionDraftStatus? status = PluginCorrectionDraftStatus.saved;
  Set<int> corrected = {};
  int retries = 0;

  void update() => notifyListeners();

  @override
  String? ownerNameForTab(String tabId) => owner;
  @override
  PluginCorrectionDraftStatus? draftStatusForTab(String tabId) => status;
  @override
  bool hasSessionForTab(String tabId) => owner != null;
  @override
  bool canEditParagraph(String tabId, String source) => owner != null;
  @override
  String editableText(String tabId, int index, String source) => source;
  @override
  bool isCorrected(String tabId, int index, String source) =>
      corrected.contains(index);
  @override
  void retryDraftWrites() => retries++;
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

bool _hasMarker(WidgetTester tester, int index) {
  final paragraph = find.byKey(ValueKey(index));
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(of: paragraph, matching: find.byType(DecoratedBox)),
      )
      .any((box) {
        final border = (box.decoration as BoxDecoration?)?.border;
        return border is BorderDirectional &&
            border.start.style != BorderStyle.none;
      });
}

void main() {
  group('באנר', () {
    late _FakeService service;

    setUp(() => service = _FakeService());
    tearDown(() => service.dispose());

    testWidgets('בלי סשן אינו מציג דבר', (tester) async {
      service.owner = null;
      service.status = null;
      await tester.pumpWidget(_app(_Banner(tabId: 't', service: service)));
      expect(find.text(_Banner.endText), findsNothing);
    });

    testWidgets('מציג את שם התוסף ומצבי השמירה', (tester) async {
      await tester.pumpWidget(_app(_Banner(tabId: 't', service: service)));
      expect(find.text(_Banner.modeText('בודק')), findsOneWidget);
      expect(
        _Banner.modeText('בודק'),
        'מצב תיקון של התוסף ‹בודק› — הנוסח המוצג כולל הצעות מקומיות; '
        'הספר אינו משתנה',
      );
      expect(find.text(_Banner.savedText), findsOneWidget);
      expect(find.text(_Banner.pageShapeText), findsNothing);

      service
        ..status = PluginCorrectionDraftStatus.saving
        ..update();
      await tester.pump();
      expect(find.text(_Banner.savingText), findsOneWidget);
      expect(find.text(_Banner.retryText), findsNothing);

      service
        ..status = PluginCorrectionDraftStatus.failed
        ..update();
      await tester.pump();
      expect(find.text(_Banner.failedText), findsOneWidget);
      await tester.tap(find.text(_Banner.retryText));
      expect(service.retries, 1);
    });

    testWidgets('בצורת הדף מציין שהתיקונים מוסתרים', (tester) async {
      await tester.pumpWidget(
        _app(_Banner(tabId: 't', pageShape: true, service: service)),
      );
      expect(find.text(_Banner.pageShapeText), findsOneWidget);
    });
  });

  testWidgets('"סיום עריכה" מסיים גם כשהתוסף אינו מגיב', (tester) async {
    final db = sqlite3.openInMemory();
    final service = PluginCorrectionSessionService()
      ..draftRepository = PluginCorrectionDraftRepository.direct(db);
    final events = <String>[];
    await tester.runAsync(
      () => service.begin(
        owner: 'p1',
        ownerName: 'בודק',
        tabId: 't',
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: 'v1',
        loadSource: (_) async => 'מקור',
        // התוסף אינו עונה לשום דבר; רק נרשם שהאירוע נשלח.
        onEvent: (topic, _) => events.add(topic),
      ),
    );
    await tester.pumpWidget(_app(_Banner(tabId: 't', service: service)));
    expect(find.text(_Banner.savedText), findsOneWidget);

    await tester.tap(find.text(_Banner.endText));
    await tester.pump();
    expect(service.hasSessionForTab('t'), isFalse);
    expect(find.text(_Banner.endText), findsNothing);

    // שחרור ה-lease ואירוע הסיום עוברים גם בזמן המדומה וגם באמיתי.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(events, contains('reader.correctionSessionEnded'));
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    db.close();
  });

  testWidgets('הסימון מופיע רק בפסקה שתוקנה', (tester) async {
    final service = _FakeService();
    addTearDown(service.dispose);
    Widget paragraph(int index) => PluginCorrectionParagraph(
      key: ValueKey(index),
      tabId: 't',
      sectionIndex: index,
      sourceText: 'מקור $index',
      settings: const RenderSettings(),
      original: Text('מקור $index'),
      service: service,
      sessionActive: true,
    );
    await tester.pumpWidget(
      _app(Column(children: [paragraph(0), paragraph(1)])),
    );
    expect(_hasMarker(tester, 0), isFalse);
    expect(_hasMarker(tester, 1), isFalse);

    service
      ..corrected = {0}
      ..update();
    await tester.pump();
    expect(_hasMarker(tester, 0), isTrue);
    expect(_hasMarker(tester, 1), isFalse);
  });
}
