import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';

class _SourceLink extends Link {
  _SourceLink(
    this.lines, {
    BookSource source = BookSource.official,
    this.lineIndexes,
  }) : super(
         heRef: 'מפרש',
         index1: 1,
         path2: 'מפרש.txt',
         index2: 3,
         index2End: lineIndexes != null
             ? lineIndexes.last + 1
             : lines.length > 1
             ? 3 + lines.length - 1
             : null,
         connectionType: 'COMMENTARY',
         targetSource: source,
       );
  final List<String> lines;
  final List<int>? lineIndexes;
  @override
  Future<String> get content async => lines.join('<br>');
  @override
  Future<List<LinkContentLine>> get contentLines async => [
    for (final (i, line) in lines.indexed)
      (lineIndex: lineIndexes?[i] ?? index2 - 1 + i, content: line),
  ];
}

void main() {
  final notesRepo = BookNotesRepository.instance;
  final namesRepo = DivineNamesRepository.instance;
  final notes =
      (BookNotesBuilder()
            ..add(2, 0, 'א', 'אלהים ראשון')
            ..addDivineName(2, 0, 0, 5, DivineNameKind.elohim)
            ..add(4, 0, 'א', 'שלישית')
            ..add(3, 0, 'א', 'אלהים שני')
            ..addDivineName(3, 0, 0, 5, DivineNameKind.elohim))
          .build();
  final names =
      (DivineNameSpansBuilder()
            ..add(2, 0, 5, DivineNameKind.elohim)
            ..add(3, 3, 8, DivineNameKind.elohim))
          .build();
  setUp(() {
    notesRepo
      ..clear()
      ..debugLoader = (title, {categoryId, required source}) async => notes;
    namesRepo
      ..clear()
      ..debugLoader = (title, {categoryId, required source}) async => names;
  });
  tearDown(() {
    notesRepo
      ..debugLoader = null
      ..clear();
    namesRepo
      ..debugLoader = null
      ..clear();
  });

  test('טווח מפרש שומר הערות ושמות לכל שורת מקור עם br פנימי', () async {
    final link = _SourceLink([
      'אלהים<br>ראשון<sup class="footnote-marker">א</sup>',
      'גם אלהים<sup class="footnote-marker">א</sup>',
    ]);
    final content = await contentWithBookNotes(link);
    final shown = resolveDivineNameMarkers(content, substituteOtherNames: true);
    expect(shown, contains('אלקים<br>ראשון'));
    expect(shown, contains('גם אלקים'));
    expect(shown, contains('אלקים ראשון'));
    expect(shown, contains('אלקים שני'));
    expect(shown.split('footnote">'), hasLength(3));
  });

  test('טווח דליל משתמש ב-lineIndex האמיתי להערות', () async {
    final content = await contentWithBookNotes(
      _SourceLink(
        [
          'א<sup class="footnote-marker">א</sup>',
          'ג<sup class="footnote-marker">א</sup>',
        ],
        lineIndexes: [2, 4],
      ),
    );
    expect(content, contains('שלישית'));
    expect(content, isNot(contains('אלהים שני')));
  });

  test('בלוקים מוכנים שומרים סמני שמות בגוף ובהערה עד לבחירת פרופיל', () async {
    final link = _SourceLink(['אלהים<sup class="footnote-marker">א</sup>']);
    final blocks = await buildCommentaryPrintBlocks(
      [
        LinkGroup(bookTitle: 'מפרש', links: [link]),
      ],
      keepHtml: true,
      protectionResolver: (_) async => BookProtection.none,
    );
    final html = blocks.last.text;
    expect(
      resolveDivineNameMarkers(html, substituteOtherNames: true),
      'אלקים<sup class="footnote-marker">א</sup><i class="footnote">אלקים ראשון</i>',
    );
    expect(
      resolveDivineNameMarkers(html, substituteOtherNames: false),
      contains('אלהים ראשון'),
    );
  });

  test('רענון מסד אינו משלב טקסט חדש עם הערות או שמות מהמטמון הישן', () async {
    final source = BookSource.attached('extra');
    expect(await notesRepo.notesFor('מפרש', source: source), same(notes));
    expect(await namesRepo.spansFor('מפרש', source: source), same(names));
    notesRepo.debugLoader = (title, {categoryId, required source}) async =>
        BookNotes.empty;
    namesRepo.debugLoader = (title, {categoryId, required source}) async =>
        DivineNameSpans.empty;
    DatabaseLibraryProvider.instance.clearCache();
    expect((await notesRepo.notesFor('מפרש', source: source)).isEmpty, isTrue);
    expect((await namesRepo.spansFor('מפרש', source: source)).isEmpty, isTrue);
  });
}
