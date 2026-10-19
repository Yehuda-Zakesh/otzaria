import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_install_screen.dart';

/// חוזה הסגירה של דיאלוג התקנת תוסף: פעולה מפורשת (התקן/ביטול) סוגרת עם
/// `true`; סגירה דרך ה-barrier מחזירה null — והמארח מתרגם אותה לביטול.
void main() {
  PluginManifest buildManifest() => PluginManifest.fromJson({
    'id': 'test.plugin',
    'name': 'תוסף בדיקה',
    'version': '1.0.0',
    'entrypoint': 'index.html',
  });

  Future<Future<bool?>> pumpAndOpenDialog(
    WidgetTester tester, {
    VoidCallback? onCancel,
    void Function(Map<String, bool>)? onConfirm,
  }) async {
    late Future<bool?> dialogResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                dialogResult = showDialog<bool>(
                  context: context,
                  builder: (_) => PluginInstallScreen(
                    manifest: buildManifest(),
                    tempDirPath: '',
                    onCancel: onCancel ?? () {},
                    onConfirm: onConfirm ?? (_) {},
                  ),
                );
              },
              child: const Text('פתח'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    return dialogResult;
  }

  testWidgets('לחיצה על ביטול סוגרת עם true ומפעילה את onCancel', (
    tester,
  ) async {
    var cancelCalled = false;
    final result = await pumpAndOpenDialog(
      tester,
      onCancel: () => cancelCalled = true,
    );

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    expect(cancelCalled, isTrue);
    expect(await result, isTrue);
  });

  testWidgets('לחיצה על התקן סוגרת עם true ומפעילה את onConfirm', (
    tester,
  ) async {
    var confirmCalled = false;
    final result = await pumpAndOpenDialog(
      tester,
      onConfirm: (_) => confirmCalled = true,
    );

    await tester.tap(find.text('התקן'));
    await tester.pumpAndSettle();

    expect(confirmCalled, isTrue);
    expect(await result, isTrue);
  });

  testWidgets('סגירה דרך ה-barrier מחזירה null — מתורגמת לביטול אצל המארח', (
    tester,
  ) async {
    var cancelCalled = false;
    final result = await pumpAndOpenDialog(
      tester,
      onCancel: () => cancelCalled = true,
    );

    // לחיצה מחוץ לדיאלוג — על ה-barrier.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(cancelCalled, isFalse);
    expect(await result, isNull);
  });
}
