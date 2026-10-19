// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  final requestedRanges = <({int startLine, int endLine})>[];

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    requestedRanges.add((startLine: startLine, endLine: endLine));
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TextBookBloc bloc;
  late TextBook book;
  late _FakeTextBookRepository repository;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    book = TextBook(title: 'ספר בדיקה');
    repository = _FakeTextBookRepository();
    bloc = TextBookBloc(
      repository: repository,
      initialState: TextBookInitial.named(book, 10, true, const []),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  blocTest<TextBookBloc, TextBookState>(
    'ApplyFullBookContent מחליף preview בתוכן מלא ושומר searchText',
    build: () => bloc,
    seed: () => TextBookLoaded(
      book: book,
      content: const ['שורת preview 1', 'שורת preview 2'],
      fontSize: 20,
      showLeftPane: true,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [10],
      pinLeftPane: false,
      searchText: 'שלום',
    ),
    act: (bloc) => bloc.add(
      const ApplyFullBookContent(
        bookTitle: 'ספר בדיקה',
        content: ['שורה מלאה 1', 'שורה מלאה 2', 'שורה מלאה 3'],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((state) => state.content.length, 'content length', 3)
          .having((state) => state.searchText, 'searchText', 'שלום'),
    ],
  );

  TextBookLoaded buildLoadedState({
    required List<String> content,
    List<int> visibleIndices = const [0],
    bool continuousReadingMode = false,
  }) => TextBookLoaded(
    book: book,
    content: content,
    supportsContinuousReadingMode: continuousReadingMode,
    continuousReadingMode: continuousReadingMode,
    fontSize: 20,
    showLeftPane: true,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: visibleIndices,
    pinLeftPane: false,
    searchText: '',
  );

  group('SetTabVisibility', () {
    final longContent = List<String>.generate(
      3000,
      (i) => 'שורה $i',
      growable: false,
    );

    // החלת טווח אמיתי מוכיחה שטעינת-טווחים עובדת לספר — תנאי לשחרור תוכן.
    const proveRangeLoading = ApplyBookContentRanges(
      bookTitle: 'ספר בדיקה',
      ranges: [
        (startLine: 1000, totalLines: 3000, lines: ['שורה 1000']),
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'הסתרת טאב משחררת תוכן מחוץ לחלון ושומרת אורך ואינדקסים',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) {
        bloc.add(proveRangeLoading);
        bloc.add(const SetTabVisibility(false));
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח המוכיח
        isA<TextBookLoaded>()
            .having((s) => s.content.length, 'content length', 3000)
            .having((s) => s.content[1000], 'שורה נראית נשמרת', 'שורה 1000')
            .having((s) => s.content[0], 'שורה רחוקה משוחררת', '')
            .having((s) => s.content[2500], 'שורה רחוקה משוחררת', ''),
      ],
    );

    test('מצב קריאה רציף משוחרר בהסתרה ופריסת הקריאה אינה זזה', () async {
      final toc = [
        for (var line = 0; line < 3000; line += 100)
          TocEntry(text: 'סימן $line', index: line),
      ];
      bloc.emit(
        buildLoadedState(
          content: longContent,
          visibleIndices: const [1050],
          continuousReadingMode: true,
        ).copyWith(tableOfContents: toc),
      );
      bloc.add(proveRangeLoading);
      final proven = await bloc.stream.first as TextBookLoaded;
      final layout = readingLayoutOf(proven);
      expect(layout.itemCount, 60);

      bloc.add(const SetTabVisibility(false));
      final released = await bloc.stream.first as TextBookLoaded;
      expect(released.content.length, 3000);
      expect(released.content[0], '');
      expect(released.content[1050], 'שורה 1050');
      expect(identical(readingLayoutOf(released), layout), isTrue);
    });

    blocTest<TextBookBloc, TextBookState>(
      'ספר במסלול preview (ללא טעינת-טווחים) אינו משוחרר בהסתרה',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) => bloc.add(const SetTabVisibility(false)),
      expect: () => const [],
    );

    blocTest<TextBookBloc, TextBookState>(
      'ספר קצר אינו משוחרר בהסתרה',
      build: () => bloc,
      seed: () => buildLoadedState(
        content: List<String>.generate(100, (i) => 'שורה $i'),
      ),
      act: (bloc) {
        bloc.add(
          const ApplyBookContentRanges(
            bookTitle: 'ספר בדיקה',
            ranges: [
              (startLine: 0, totalLines: 100, lines: ['שורה 0']),
            ],
          ),
        );
        bloc.add(const SetTabVisibility(false));
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח בלבד — אין emission שחרור
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'אצוות חימום בתור אינן מוחלות בזמן שהטאב מוסתר',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) {
        bloc.add(proveRangeLoading);
        bloc.add(const SetTabVisibility(false));
        bloc.add(
          const ApplyBookContentRanges(
            bookTitle: 'ספר בדיקה',
            ranges: [
              (startLine: 0, totalLines: 3000, lines: ['תוכן שחזר']),
            ],
          ),
        );
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח המוכיח
        // emission השחרור — האצווה שאחריו נבלעת
        isA<TextBookLoaded>().having((s) => s.content[0], 'line 0', ''),
      ],
    );

    blocTest<TextBookBloc, TextBookState>(
      'אחרי חזרה לנראות אצוות תוכן שבות ומוחלות',
      build: () => bloc,
      seed: () =>
          buildLoadedState(content: longContent, visibleIndices: const [1000]),
      act: (bloc) async {
        bloc.add(proveRangeLoading);
        bloc.add(const SetTabVisibility(false));
        bloc.add(const SetTabVisibility(true));
        bloc.add(
          const ApplyBookContentRanges(
            bookTitle: 'ספר בדיקה',
            ranges: [
              (startLine: 0, totalLines: 3000, lines: ['תוכן שחזר']),
            ],
          ),
        );
      },
      expect: () => [
        isA<TextBookLoaded>(), // החלת הטווח המוכיח
        isA<TextBookLoaded>().having((s) => s.content[0], 'line 0', ''),
        isA<TextBookLoaded>().having(
          (s) => s.content[0],
          'line 0',
          'תוכן שחזר',
        ),
      ],
    );
  });

  blocTest<TextBookBloc, TextBookState>(
    'ApplyBookContentRanges מחיל כמה טווחים ב-emission יחיד',
    build: () => bloc,
    seed: () => TextBookLoaded(
      book: book,
      content: const ['שורה 0', 'שורה 1'],
      fontSize: 20,
      showLeftPane: true,
      showSplitView: false,
      activeCommentators: const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      visibleIndices: const [0],
      pinLeftPane: false,
      searchText: '',
    ),
    act: (bloc) => bloc.add(
      const ApplyBookContentRanges(
        bookTitle: 'ספר בדיקה',
        ranges: [
          (startLine: 2, totalLines: 6, lines: ['שורה 2', 'שורה 3']),
          (startLine: 4, totalLines: 6, lines: ['שורה 4', 'שורה 5']),
        ],
      ),
    ),
    expect: () => [
      isA<TextBookLoaded>()
          .having((state) => state.content.length, 'content length', 6)
          .having((state) => state.content[3], 'line 3', 'שורה 3')
          .having((state) => state.content[5], 'line 5', 'שורה 5'),
    ],
  );

  test('פסקה רציפה שלא נטענה כולה מבקשת את כל טווח שורותיה', () async {
    // שורות 1..1999 בין שתי כותרות (נחתכות לפריטים); רק סביב שורה 1000 טעון.
    const lineCount = 2100;
    final toc = [
      TocEntry(text: 'פתיחה', index: 0),
      TocEntry(text: 'סיום', index: 2000),
    ];
    final layout = continuousReadingLayout(
      lineCount: lineCount,
      tableOfContents: toc,
    );
    final item = layout.itemForLine(1000);
    final flags = [
      for (var i = 0; i < lineCount; i++) i >= 990 && i <= 1010,
    ];
    bloc.emit(
      buildLoadedState(
        content: [
          for (var i = 0; i < lineCount; i++) flags[i] ? 'שורה $i' : '',
        ],
        visibleIndices: const [0],
        continuousReadingMode: true,
      ).copyWith(
        loadedLineFlags: flags,
        showLeftPane: false,
        tableOfContents: toc,
      ),
    );
    bloc.add(const UpdateVisibleIndecies([999, 1000, 1001]));
    await bloc.stream.first;
    await Future<void>.delayed(Duration.zero);

    expect(repository.requestedRanges, isNotEmpty);
    final requested = repository.requestedRanges.last;
    expect(layout.lineCountOf(item), greaterThan(21));
    expect(requested.startLine, lessThanOrEqualTo(layout.firstLineOf(item)));
    expect(requested.endLine, greaterThanOrEqualTo(layout.lastLineOf(item)));
  });
}
