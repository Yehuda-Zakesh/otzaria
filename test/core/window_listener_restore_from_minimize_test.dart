import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// חזרה של החלון ממיזעור היא הרגע היחיד שבו ה-WebView של תוסף נשאר בלי
/// מקלדת (ראו `PluginRuntimeDispatcher.restoreKeyboardFocusAfterWindowRestore`),
/// ולכן ההעברה הנייטיבית נתלית דווקא בו ולא בכל אירוע מצב-חלון.
///
/// `window_manager` משדר על החזרה `restore`, ואם החלון היה מוגדל לפני
/// המיזעור — `maximize`. שני האירועים האלה מגיעים גם בלי מיזעור כלל
/// (המשתמש הגדיל את החלון), ולכן ההבחנה נשענת על מיזעור שקדם להם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('מיזעור ואז restore — דיווח אחד', () {
    final listener = AppWindowListener();
    var calls = 0;
    listener.onWindowRestoredFromMinimize = () => calls++;

    listener.onWindowMinimize();
    listener.onWindowRestore();

    expect(calls, 1);
  });

  test('חלון מוגדל: מיזעור ואז maximize — דיווח אחד', () {
    final listener = AppWindowListener();
    var calls = 0;
    listener.onWindowRestoredFromMinimize = () => calls++;

    listener.onWindowMinimize();
    listener.onWindowMaximize();

    expect(calls, 1);
  });

  test('הגדלה או שחזור בלי מיזעור — אין דיווח', () {
    final listener = AppWindowListener();
    var calls = 0;
    listener.onWindowRestoredFromMinimize = () => calls++;

    listener.onWindowMaximize();
    listener.onWindowRestore();

    expect(calls, 0);
  });

  test('המיזעור נצרך פעם אחת — האירוע הבא אינו חוזר עליו', () {
    final listener = AppWindowListener();
    var calls = 0;
    listener.onWindowRestoredFromMinimize = () => calls++;

    listener.onWindowMinimize();
    listener.onWindowRestore();
    listener.onWindowMaximize();
    listener.onWindowRestore();

    expect(calls, 1);
  });

  test('שני מיזעורים — שני דיווחים', () {
    final listener = AppWindowListener();
    var calls = 0;
    listener.onWindowRestoredFromMinimize = () => calls++;

    listener.onWindowMinimize();
    listener.onWindowRestore();
    listener.onWindowMinimize();
    listener.onWindowRestore();

    expect(calls, 2);
  });

  test('מזעור מסתיר את התוספים מהדיספצ\'ר, והשחזור מחזיר לפני ה-callback', () {
    final dispatcher = PluginRuntimeDispatcher.instance;
    const key = (pluginId: 'p', instanceId: 'i');
    dispatcher.resetVisibilityForTesting();
    addTearDown(dispatcher.resetVisibilityForTesting);
    dispatcher.setVisiblePluginInstances({key});
    final listener = AppWindowListener();
    bool? shownAtCallback;
    listener.onWindowRestoredFromMinimize = () =>
        shownAtCallback = dispatcher.isInstanceShown(key);

    listener.onWindowMinimize();
    expect(dispatcher.isInstanceShown(key), isFalse);
    listener.onWindowRestore();

    expect(shownAtCallback, isTrue);
  });
}
