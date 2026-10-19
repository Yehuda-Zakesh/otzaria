import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('הנעיצה אינה עוקפת מסך צר', () {
    setUp(() async {
      await Settings.setValue('key-pin-sidebar', true);
      await Settings.setValue('key-default-sidebar-open', true);
    });

    test('shouldAutoOpenReadingLeftPane — סגור בטלפון, פתוח בשולחני', () {
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 411), isFalse);
      expect(shouldAutoOpenReadingLeftPane(screenWidth: 1400), isTrue);
    });

    test('resolveInitialReadingLeftPaneVisibility — סגור בטלפון', () {
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: false,
          hasSearchText: false,
          screenWidth: 411,
        ),
        isFalse,
      );
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: false,
          hasSearchText: false,
          screenWidth: 1400,
        ),
        isTrue,
      );
    });

    test('בקשה מפורשת פותחת גם בטלפון', () {
      expect(
        resolveInitialReadingLeftPaneVisibility(
          explicitOpen: true,
          hasSearchText: false,
          screenWidth: 411,
        ),
        isTrue,
      );
    });

    test('מצב שמור ב-JSON גובר על הנעיצה', () {
      expect(
        resolveRestoredReadingLeftPaneState(
          {'showLeftPane': true},
          screenWidth: 411,
        ),
        isTrue,
      );
      expect(
        resolveRestoredReadingLeftPaneState(const {}, screenWidth: 411),
        isFalse,
      );
    });
  });

  test('בלי נעיצה ובלי "פתוח כברירת מחדל" — סגור בכל רוחב', () async {
    await Settings.setValue('key-pin-sidebar', false);
    await Settings.setValue('key-default-sidebar-open', false);

    expect(shouldAutoOpenReadingLeftPane(screenWidth: 1400), isFalse);
    expect(shouldAutoOpenReadingLeftPane(screenWidth: 411), isFalse);
  });

  test('"פתוח כברירת מחדל" בלבד — פתוח רק בשולחני', () async {
    await Settings.setValue('key-pin-sidebar', false);
    await Settings.setValue('key-default-sidebar-open', true);

    expect(shouldAutoOpenReadingLeftPane(screenWidth: 1400), isTrue);
    expect(shouldAutoOpenReadingLeftPane(screenWidth: 411), isFalse);
  });
}
