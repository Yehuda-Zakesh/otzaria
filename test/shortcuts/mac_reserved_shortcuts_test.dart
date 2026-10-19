import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

import '../helpers/memory_settings_cache.dart';

/// ב-Mac ה-token `ctrl` נפתר כ-Command, ותפריט המערכת בולע ⌘H (הסתרת היישום)
/// ו-⌘M (מזעור) לפני שהאירוע מגיע ל-Flutter — issue #1269.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const historyKey = 'key-shortcut-open-history';
  const moreKey = 'key-shortcut-open-more';

  late MemorySettingsCache cache;
  late SettingsRepository repository;

  setUp(() async {
    cache = MemorySettingsCache();
    await Settings.init(cacheProvider: cache);
    repository = SettingsRepository();
    addTearDown(() => ShortcutHelper.isMacForTesting = null);
  });

  group('ברירות המחדל ב-Mac', () {
    setUp(() => ShortcutHelper.isMacForTesting = true);

    test('אינן משתמשות במקש שתפריט המערכת בולע', () {
      for (final value in ShortcutValidator.defaultShortcuts.values) {
        expect(ShortcutValidator.macReservedShortcuts, isNot(contains(value)));
      }
    });

    test('היסטוריה וכלים מקבלים קיצור חלופי', () {
      expect(ShortcutValidator.defaultShortcuts[historyKey], 'ctrl+y');
      expect(ShortcutValidator.defaultShortcuts[moreKey], 'ctrl+shift+m');
    });

    test('החלופות אינן מתנגשות בקיצור אחר', () {
      final others = ShortcutValidator.defaultShortcuts.entries
          .where((entry) => entry.key != historyKey && entry.key != moreKey)
          .map((entry) => entry.value);
      expect(others, isNot(contains('ctrl+y')));
      expect(others, isNot(contains('ctrl+shift+m')));
    });
  });

  group('ברירות המחדל מחוץ ל-Mac', () {
    setUp(() => ShortcutHelper.isMacForTesting = false);

    test('נשארות כשהיו', () {
      expect(ShortcutValidator.defaultShortcuts[historyKey], 'ctrl+h');
      expect(ShortcutValidator.defaultShortcuts[moreKey], 'ctrl+m');
    });
  });

  group('ניקוי קיצור שמור שנבלע ב-Mac', () {
    Future<void> storeShortcut(String key, String value) async {
      await cache.setString(key, value);
      final stored = Map<String, String>.from(
        (cache.getValue<Map<dynamic, dynamic>>('shortcuts') ??
                <dynamic, dynamic>{})
            .cast<String, String>(),
      );
      stored[key] = value;
      await cache.setObject('shortcuts', stored);
    }

    test('מוחק ⌘H שנשמר באיפוס ומחזיר את החלופה', () async {
      ShortcutHelper.isMacForTesting = true;
      await storeShortcut(historyKey, 'ctrl+h');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(historyKey), isNull);
      expect((await repository.getShortcuts())[historyKey], 'ctrl+y');
    });

    test('אינו נוגע באותו ערך מחוץ ל-Mac', () async {
      ShortcutHelper.isMacForTesting = false;
      await storeShortcut(historyKey, 'ctrl+h');

      await repository.removeUnrecognizedShortcuts();

      expect(cache.getString(historyKey), 'ctrl+h');
    });
  });
}
