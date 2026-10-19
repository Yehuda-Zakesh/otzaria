import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

/// `UpdatePageNumber` מצלם את ה-state בכניסה למטפל. כל `await` בדרך ל-emit
/// מאפשר לאירוע אחר לפלוט מצב חדש, וה-emit של הצילום המיושן דורס אותו — כאן
/// הקישורים שנטענו ברקע נמחקו בגלילה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  test('קישורים שנטענו מיד אחרי מעבר עמוד אינם נדרסים', () async {
    final bloc = await _loadedBloc();

    expect((bloc.state as PdfBookLoaded).links, isEmpty);

    bloc.add(const UpdatePageNumber(pageNumber: 7));
    bloc.add(
      LoadHeadingsAndLinks(
        links: [
          Link(
            heRef: 'א',
            index1: 10,
            path2: 'x.txt',
            index2: 1,
            connectionType: 'commentary',
          ),
        ],
      ),
    );

    await _waitFor(
      () => (bloc.state as PdfBookLoaded).currentPageNumber == 7,
      description: 'מספר העמוד התעדכן ל-7',
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final state = bloc.state as PdfBookLoaded;
    expect(
      state.links,
      hasLength(1),
      reason:
          'LoadHeadingsAndLinks נפלט אחרי הצילום — אסור שה-emit של מעבר העמוד ידרוס אותו',
    );
    expect(state.currentPageNumber, 7);

    await bloc.close();
  });
}

/// bloc במצב Loaded עם `outline` לא-null — התנאי שמפעיל את חישוב הכותרת
/// מה-outline, שהיה בעבר ה-`await` היחיד במטפל.
Future<PdfBookBloc> _loadedBloc() async {
  final tab = PdfBookTab(
    book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
    pageNumber: 1,
  );
  final bloc = PdfBookBloc(
    tab: tab,
    initialState: PdfBookInitial(book: tab.book, initialPageNumber: 1),
    pdfrxInit: () async {},
  );

  bloc.add(
    DocumentReady(
      documentRef: _FakeDocumentRef(),
      totalPages: 50,
      outline: const [],
    ),
  );

  await _waitFor(
    () => bloc.state is PdfBookLoaded,
    description: 'מצב טעון',
  );
  return bloc;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$description not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FakeDocumentRef extends Fake implements PdfDocumentRef {}
