import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_webview_failed_view.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('he', 'IL'),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('ההסבר הכללי מוצג כשאין אמולציית ARM', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PluginWebViewFailedView(
          pluginName: 'מחשבון',
          onRetry: () {},
        ),
      ),
    );

    expect(find.textContaining('לא ניתן להפעיל את התוסף "מחשבון"'), findsOne);
    expect(find.textContaining('מבוסס מעבד ARM'), findsNothing);
  });

  testWidgets('ההסבר הייעודי מוצג במחשב ARM', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PluginWebViewFailedView(
          isEmulatedOnArm: true,
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('התוספים אינם נתמכים עדיין במחשב זה'), findsOne);
    expect(find.textContaining('מבוסס מעבד ARM'), findsOne);
  });

  testWidgets('פרטי השגיאה נגללים לפתיחה ומוצגים כטקסט נבחר', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PluginWebViewFailedView(
          errorDetails: 'HRESULT 0x80070005 Access is denied.',
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('פרטי השגיאה'), findsOne);
    await tester.tap(find.text('פרטי השגיאה'));
    await tester.pumpAndSettle();
    expect(find.text('HRESULT 0x80070005 Access is denied.'), findsOne);
  });

  testWidgets('כפתור "נסה שוב" מפעיל את ה-callback', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _wrap(PluginWebViewFailedView(onRetry: () => retried++)),
    );

    await tester.tap(find.text('נסה שוב'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('נפילה חוזרת מציגה הסבר משלה ו"נסה שוב"', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _wrap(
        PluginWebViewFailedView(
          pluginName: 'מחשבון',
          kind: PluginWebViewFailureKind.crashed,
          isEmulatedOnArm: true,
          onRetry: () => retried++,
        ),
      ),
    );

    expect(find.textContaining('התוסף "מחשבון" הפסיק לפעול'), findsOne);
    expect(find.textContaining('נסגר שוב ושוב'), findsOne);
    expect(find.textContaining('מבוסס מעבד ARM'), findsNothing);
    await tester.tap(find.text('נסה שוב'));
    expect(retried, 1);
  });
}
