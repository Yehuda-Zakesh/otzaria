import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../test_helpers/pdf_document_dispose.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';

import '../../helpers/memory_settings_cache.dart';

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;
  late File pdfFile;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDirectory = await Directory.systemTemp.createTemp(
      'book_preview_context_menu_',
    );
    pdfFile = File('${tempDirectory.path}/preview.pdf');
    final source = pw.Document();
    source.addPage(
      pw.Page(
        build: (context) => pw.Center(child: pw.Text('copy from preview')),
      ),
    );
    await pdfFile.writeAsBytes(await source.save());
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => tempDirectory.path,
            _ => null,
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  tearDownAll(() async {
    await tempDirectory.delete(recursive: true);
  });

  testWidgets('בחירה, לחיצה ימנית והעתקה משתמשות בתפריט אוצריא', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settingsBloc = _FakeSettingsBloc();
    addTearDown(settingsBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox.expand(
              child: BookPreviewPanel(
                book: PdfBook(title: 'מסמך בדיקה', path: pdfFile.path),
              ),
            ),
          ),
        ),
      ),
    );

    PdfViewer viewer() => tester.widget<PdfViewer>(find.byType(PdfViewer));
    final controller = viewer().controller!;
    // pdfium עונה מ-isolate אמיתי: בלי runAsync ההמשך נתקע בתור ה-microtasks
    // של ה-FakeAsync, ו-await ישיר עליו לא חוזר לעולם.
    Future<bool> pumpUntil(bool Function() condition) async {
      for (var i = 0; i < 40 && !condition(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      return condition();
    }

    bool hasLayout() {
      if (!controller.isReady) return false;
      try {
        controller.viewSize;
        return true;
      } catch (_) {
        // ה-controller נעשה מוכן לפני ה-layout הראשון.
        return false;
      }
    }

    expect(await pumpUntil(hasLayout), isTrue);
    final document = controller.document;

    final selecting = controller.textSelectionDelegate.selectAllText();
    expect(
      await pumpUntil(() => controller.textSelectionDelegate.hasSelectedText),
      isTrue,
    );
    await selecting;
    await tester.pumpAndSettle();

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final center = tester.getCenter(find.byType(PdfViewer));
    final rightClick = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await rightClick.addPointer(location: center);
    addTearDown(rightClick.removePointer);
    await rightClick.down(center);
    await tester.pump();
    await rightClick.up();
    await tester.pumpAndSettle();

    expect(find.text('העתק'), findsOneWidget);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    final copyButton = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('העתק'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(copyButton.onPressed, isNotNull);
    await tester.tap(find.text('העתק'));
    await tester.pumpAndSettle();
    expect(clipboardText, contains('copy from preview'));

    await tester.longPressAt(center);
    await tester.pumpAndSettle();
    expect(find.text('העתק'), findsOneWidget);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await disposePdfDocument(tester, document);
  });
}
