import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:pdfrx/pdfrx.dart';

List<int> _blankPdf(int pageCount) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(pageCount, (i) => '${i + 3} 0 R').join(' ')}] /Count $pageCount >>',
    for (var i = 0; i < pageCount; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return latin1.encode(out.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria-pdf-thumbs-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => switch (call.method) {
            'getTemporaryDirectory' => tempDir.path,
            _ => null,
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  RawImage firstThumbnail(WidgetTester tester) =>
      tester.widget<RawImage>(find.byType(RawImage).first);

  testWidgets('תמונה ממוזערת שחוזרת למסך מוצגת מהמטמון בלי רינדור חוזר', (
    tester,
  ) async {
    final document = (await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      return PdfDocument.openData(
        Uint8List.fromList(_blankPdf(40)),
        sourceName: 'thumbs.pdf',
      );
    }))!;
    final ref = PdfDocumentRefDirect(document);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 600,
            child: ThumbnailsView(documentRef: ref, controller: null),
          ),
        ),
      ),
    );
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(RawImage).evaluate().isNotEmpty &&
          firstThumbnail(tester).image != null) {
        break;
      }
    }
    expect(firstThumbnail(tester).image, isNotNull);

    final list = find.byType(Scrollable);
    tester.state<ScrollableState>(list).position.jumpTo(266.0 * 30);
    await tester.pump();
    expect(find.text('1'), findsNothing);
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump();

    expect(firstThumbnail(tester).image, isNotNull);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => document.dispose());
  });
}
