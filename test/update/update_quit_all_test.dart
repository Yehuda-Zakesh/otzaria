import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';

/// המעדכן החיצוני מחליף קבצים רק אחרי שהתהליך יצא, ולכן "התקן כעת" יוצא מכל
/// החלונות דרך [AppQuit.quitAll]. בריבוי תצוגות סגירת הראשי רק מסתירה אותו,
/// והתהליך היה נשאר חי בזכות חלונות ה-Dart (G1).
void main() {
  late List<String> updateSource;

  setUpAll(() {
    updateSource = [
      for (final file in Directory(
        'lib/update',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart'))
          ...file.readAsLinesSync().where(
            (line) => !line.trimLeft().startsWith('//'),
          ),
    ];
    expect(updateSource, isNotEmpty, reason: 'הסריקה חייבת לרוץ משורש החבילה');
  });

  tearDown(() {
    AppQuit.resetForTest();
  });

  test('מסלול העדכון יוצא מכל החלונות דרך AppQuit', () {
    expect(
      updateSource.any((line) => line.contains('AppQuit.quitAll(')),
      isTrue,
    );
    expect(
      updateSource.any(
        (line) => line.contains('_appWindow.close('),
      ),
      isFalse,
      reason: 'סגירת הראשי בלבד משאירה את התהליך חי כשחלונות Dart פתוחים',
    );
  });

  test('מסלול העדכון אינו מכבה חלונות אחרים בכפייה', () {
    for (final forced in ['forceTerminate', 'quitApplication(', 'exit(0)']) {
      expect(
        updateSource.any((line) => line.contains(forced)),
        isFalse,
        reason: '$forced היה עוקף את שומרי הסגירה ואת שטיפת הסשנים',
      );
    }
  });

  test('מסלול היציאה של התהליך, לא הסתרת הראשי', () async {
    var quitProcess = 0;
    AppQuit.install(() async => quitProcess++);
    final window = _RecordingWindow();

    await AppQuit.quitAll(AppQuitReason.update, window: window);

    expect(quitProcess, 1);
    expect(window.closes, 0, reason: 'סגירה רגילה רק מסתירה את הראשי');
  });

  test('בלי מסלול מותקן: נופל לסגירה המנומסת', () async {
    final window = _RecordingWindow();

    await AppQuit.quitAll(AppQuitReason.update, window: window);

    expect(window.closes, 1);
  });
}

class _RecordingWindow extends Fake implements AppWindowController {
  int closes = 0;

  @override
  Future<void> close() async => closes++;
}
