import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/find_ref_recent_store.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(FindRefRecentStore.clear);

  test('ללא היסטוריה מוחזרת רשימה ריקה', () {
    expect(FindRefRecentStore.load(), isEmpty);
  });

  test('שאילתה נשמרת בראש הרשימה', () {
    FindRefRecentStore.remember('בראשית פרק א');
    FindRefRecentStore.remember('שו"ע או"ח יב');

    expect(FindRefRecentStore.load(), ['שו"ע או"ח יב', 'בראשית פרק א']);
  });

  test('שאילתה חוזרת עולה לראש ואינה נכפלת', () {
    FindRefRecentStore.remember('בראשית פרק א');
    FindRefRecentStore.remember('שו"ע או"ח יב');
    FindRefRecentStore.remember('בראשית פרק א');

    expect(FindRefRecentStore.load(), ['בראשית פרק א', 'שו"ע או"ח יב']);
  });

  test('רווחים בקצוות מנוכים, ושאילתה ריקה אינה נשמרת', () {
    FindRefRecentStore.remember('  בראשית פרק א  ');
    FindRefRecentStore.remember('   ');

    expect(FindRefRecentStore.load(), ['בראשית פרק א']);
  });

  test('הרשימה נחתכת למכסה', () {
    for (var i = 0; i < FindRefRecentStore.maxEntries + 5; i++) {
      FindRefRecentStore.remember('שאילתה $i');
    }

    final entries = FindRefRecentStore.load();
    expect(entries, hasLength(FindRefRecentStore.maxEntries));
    expect(entries.first, 'שאילתה ${FindRefRecentStore.maxEntries + 4}');
  });

  test('ערך פגום בהגדרות אינו זורק', () {
    Settings.setValue<String>('key-find-ref-recent-queries', 'not-json');

    expect(FindRefRecentStore.load(), isEmpty);
  });
}
