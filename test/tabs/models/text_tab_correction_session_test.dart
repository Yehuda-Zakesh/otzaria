import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _FakeBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _FakeBloc()
    : super(TextBookInitial(TextBook(title: 'ספר'), 0, false, const [])) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// סיום הסשן (שמירה, שחרור ה-lease ואירוע) רץ אחרי הסגירה עצמה.
Future<void> _idle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = PluginCorrectionSessionService.instance;
  final events = <(String, Map<String, dynamic>)>[];
  late Database db;
  var books = 0;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    events.clear();
    db = sqlite3.openInMemory();
    service.draftRepository = PluginCorrectionDraftRepository.direct(db);
  });

  tearDown(() async {
    service.removeOwner('owner');
    await _idle();
    db.close();
  });

  TextBookTab newTab() => TextBookTab(
    book: TextBook(id: 1, title: 'ספר'),
    index: 0,
    blocOverride: _FakeBloc(),
  );

  // ספר נפרד לכל לשונית: אותו תוסף אינו פותח שני סשנים על אותו ספר.
  Future<void> begin(TextBookTab tab) => service.begin(
    owner: 'owner',
    tabId: PluginCorrectionSessionService.tabIdFor(tab),
    bookId: 'ספר',
    bookUid: 'id:${++books}',
    libraryVersion: '1',
    loadSource: (_) async => 'מקור',
    onEvent: (topic, payload) => events.add((topic, payload)),
  );

  test('סגירת הלשונית מסיימת את הסשן שלה עם tab_closed', () async {
    final tab = newTab();
    await begin(tab);
    final id = PluginCorrectionSessionService.tabIdFor(tab);
    expect(service.hasSessionForTab(id), isTrue);

    tab.dispose();

    expect(service.hasSessionForTab(id), isFalse);
    await _idle();
    expect(events.single.$1, 'reader.correctionSessionEnded');
    expect(events.single.$2['reason'], 'tab_closed');
  });

  test('סגירת לשונית אחת אינה מסיימת סשן של לשונית אחרת', () async {
    final closing = newTab();
    final staying = newTab();
    await begin(closing);
    await begin(staying);

    closing.dispose();
    await _idle();

    expect(
      service.hasSessionForTab(
        PluginCorrectionSessionService.tabIdFor(staying),
      ),
      isTrue,
    );
    staying.dispose();
  });

  test('לשונית שמעולם לא קיבלה מזהה נסגרת בלי לגעת בסשנים', () async {
    final other = newTab();
    await begin(other);
    final tab = newTab();

    tab.dispose();
    await _idle();

    expect(PluginCorrectionSessionService.knownTabIdFor(tab), isNull);
    expect(
      service.hasSessionForTab(PluginCorrectionSessionService.tabIdFor(other)),
      isTrue,
    );
    expect(events, isEmpty);
    other.dispose();
  });
}
