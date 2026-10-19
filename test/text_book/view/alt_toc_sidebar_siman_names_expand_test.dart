import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/alt_toc_sidebar_view.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';

import '../../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _title = 'ספר אישי';
const _filePath = '/books/ספר אישי.txt';

UserAltTocEntryData _entry(String text, int line) => UserAltTocEntryData(
  level: 1,
  text: text,
  lineIndex: line,
  parentIndex: null,
  hasChildren: false,
  isLastChild: false,
);

void main() {
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria-siman-names-');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      tempDir.path,
    );
    await UserBooksDatabaseHolder.instance.close();

    final userDb = (await UserBooksDatabaseHolder.instance.repository).database;
    final raw = await userDb.database;
    raw.execute("INSERT INTO source (name) VALUES ('external')");
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, filePath, fileType) '
      "VALUES (7, 1, '$_title', '$_filePath', 'txt')",
    );
    // Seifim is written first, so SimanNames has the larger structure id.
    await UserContentRepository(userDb).replaceBookHeadings(
      raw.lastInsertRowId,
      [
        UserAltTocStructureData(
          key: 'Seifim',
          heTitle: 'סעיפים',
          entries: [_entry('סעיף ראשון', 0)],
        ),
        UserAltTocStructureData(
          key: 'SimanNames',
          heTitle: 'הלכות וסימנים',
          entries: [_entry('סימן ראשון — הלכות השכמה', 0)],
        ),
      ],
      source: 'test',
    );
  });

  tearDown(() async {
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('SimanNames נפתח לפי המיקום גם כש-Seifim קודם לו במסד', (
    tester,
  ) async {
    final book = TextBook(
      title: _title,
      filePath: _filePath,
      source: BookSource.user,
    );
    final bloc = _TestTextBookBloc(
      TextBookLoaded(
        book: book,
        showLeftPane: true,
        content: List.generate(10, (i) => 'שורה $i'),
        fontSize: 18,
        showSplitView: false,
        activeCommentators: const [],
        commentatorGroups: const [],
        availableCommentators: const [],
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        removeNikud: false,
        visibleIndices: const [3],
        selectedIndex: null,
        pinLeftPane: false,
        searchText: '',
      ),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TextBookBloc>.value(
            value: bloc,
            child: SizedBox(
              width: 400,
              height: 800,
              child: AltTocSidebarView(
                book: book,
                closeLeftPaneCallback: () {},
                lines: LineScrollController(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('הלכות וסימנים'), findsOneWidget);
    expect(find.text('סעיפים'), findsOneWidget);
    expect(find.text('סימן ראשון — הלכות השכמה'), findsOneWidget);
    expect(find.text('סעיף ראשון'), findsNothing);
  });
}
