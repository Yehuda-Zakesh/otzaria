import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import '../../helpers/memory_settings_cache.dart';

class _StubTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _StubTextBookBloc()
    : super(
        TextBookInitial.named(
          TextBook(title: 'ספר בדיקה'),
          0,
          false,
          const [],
        ),
      ) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  late Future<String?> Function(TextBook, int) originalResolver;
  setUp(() => originalResolver = TextBookTab.locationTitleResolver);
  tearDown(() => TextBookTab.locationTitleResolver = originalResolver);

  TextBookTab makeTab({int index = 7}) {
    final tab = TextBookTab(
      book: TextBook(title: 'ספר בדיקה'),
      index: index,
      blocOverride: _StubTextBookBloc(),
    );
    return tab;
  }

  group('TextBookTab.ensureLocationTitle', () {
    test('ממלא כותרת ריקה מהפותר לפי הספר והאינדקס השמור', () async {
      var calls = 0;
      TextBookTab.locationTitleResolver = (book, index) async {
        calls++;
        return '${book.title}: פרק ${index + 1} ';
      };
      final tab = makeTab(index: 3);
      addTearDown(tab.dispose);

      await tab.ensureLocationTitle();
      await tab.ensureLocationTitle();

      expect(tab.currentTitle.value, 'ספר בדיקה: פרק 4');
      expect(calls, 1, reason: 'הפתרון נשמר ואינו שולף שוב');
    });

    test('אינו דורס כותרת חיה שכבר התקבלה מה-BLoC', () async {
      var calls = 0;
      TextBookTab.locationTitleResolver = (_, _) async {
        calls++;
        return 'מיקום מה-DB';
      };
      final tab = makeTab();
      addTearDown(tab.dispose);
      tab.currentTitle.value = 'מיקום חי';

      await tab.ensureLocationTitle();

      expect(tab.currentTitle.value, 'מיקום חי');
      expect(calls, 0);
    });

    test('כותרת חיה שהגיעה בזמן השליפה מנצחת את תוצאת ה-DB', () async {
      final gate = Completer<String?>();
      TextBookTab.locationTitleResolver = (_, _) => gate.future;
      final tab = makeTab();
      addTearDown(tab.dispose);

      final pending = tab.ensureLocationTitle();
      tab.currentTitle.value = 'מיקום חי';
      gate.complete('מיקום מה-DB');
      await pending;

      expect(tab.currentTitle.value, 'מיקום חי');
    });

    test('תוצאה ריקה אינה נשמרת — הקריאה הבאה מנסה שוב', () async {
      var calls = 0;
      TextBookTab.locationTitleResolver = (_, _) async {
        calls++;
        return calls == 1 ? null : 'מיקום';
      };
      final tab = makeTab();
      addTearDown(tab.dispose);

      await tab.ensureLocationTitle();
      expect(tab.currentTitle.value, isEmpty);

      await tab.ensureLocationTitle();
      expect(tab.currentTitle.value, 'מיקום');
      expect(calls, 2);
    });

    test('טאב שנסגר לפני סיום השליפה אינו נוגע ב-notifier שנפטר', () async {
      final gate = Completer<String?>();
      TextBookTab.locationTitleResolver = (_, _) => gate.future;
      final tab = makeTab();

      final pending = tab.ensureLocationTitle();
      tab.dispose();
      gate.complete('מיקום');

      await expectLater(pending, completes);
    });
  });
}
