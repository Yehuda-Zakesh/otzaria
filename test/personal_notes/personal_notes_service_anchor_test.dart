import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

class _MemoryNotesDb implements PersonalNotesDatabase {
  final notes = <String, PersonalNote>{};

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async =>
      notes.values.where((note) => note.bookId == bookId).toList();

  @override
  Future<void> insertNote(PersonalNote note) async => notes[note.id] = note;

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> changed) async {
    for (final note in changed) {
      notes[note.id] = note;
    }
  }

  @override
  Future<PersonalNote?> getNote(String id) async => notes[id];

  @override
  Future<void> updateNote(PersonalNote note) async => notes[note.id] = note;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('בחירה ללא פיסוק מאמצע השורה נשארת במקומה לאחר טעינה מחדש', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    const raw =
        'אחד שתים שלוש ארבע חמש שש שבע שמונה תשע רבי יוחנן, מאי דכתיב? עוד טקסט';
    final shown = removePunctuation(raw);
    final selected = shown
        .substring(shown.indexOf('רבי יוחנן'), shown.indexOf('עוד טקסט'))
        .trim();

    final added = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: selected,
    )).single;
    expect(added.anchorText, isNotNull);
    expect(added.status, PersonalNoteStatus.located);

    final reloaded = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: raw,
    )).single;
    expect(reloaded.status, PersonalNoteStatus.located);
    expect(reloaded.lineNumber, 1);
    expect(reloaded.anchorStart, raw.indexOf('רבי יוחנן'));
  });

  test('רמז המיקום של תצוגה בלי פיסוק עובר דרך שירות ההערות', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    final raw = '${List.filled(40, 'א,').join()} מילה משהו מילה';
    final shown = removePunctuation(raw);

    final note = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: 'מילה',
      selectionColumn: shown.lastIndexOf('מילה'),
      punctuationHidden: true,
    )).single;

    expect(note.anchorStart, raw.lastIndexOf('מילה'));
  });

  test('עוגן הערה משתמש בבחירת המקור ושומר כותרת תצוגה נפרדת', () async {
    const raw = 'מילה <b>יהוה</b> מילה אמר מילה <i>יהוה</i> מילה';
    const settings = RenderSettings(
      replaceHolyNames: true,
      formatParentheses: false,
    );
    final map = const TextSourceMapService().build(
      bookId: 'ספר',
      sectionIndex: 0,
      rawText: raw,
      settings: settings,
    );
    final selectedText = 'יקוק';
    final selection = const ReaderSelectionService().buildFromRenderedSelection(
      bookId: 'ספר',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: raw,
      settings: settings,
      selectedText: selectedText,
      startHint: map.renderedText.lastIndexOf(selectedText),
    );
    final sourceText = stripHtmlIfNeeded(raw);
    final note =
        (await PersonalNotesService(
              database: _MemoryNotesDb(),
              random: Random(1),
            ).addNote(
              bookId: 'ספר',
              bookContent: raw,
              lineNumber: 1,
              content: 'הערה',
              contentPlain: 'הערה',
              contentFormat: PersonalNoteContentFormat.plain,
              selectedText: selectedText,
              sourceSelectedText: selection!.sourceSelectedText,
              sourceSelectionOffset: selection.sourceRange.start.utf16,
            ))
            .single;

    expect(note.displayTitle, selectedText);
    expect(note.anchorText, 'יהוה');
    expect(note.anchorStart, raw.lastIndexOf('יהוה'));
    expect(note.anchorPrefix, contains('אמר מילה'));
    expect(note.anchorSuffix, contains(' מילה'));
    expect(sourceText.lastIndexOf('יהוה'), selection.sourceRange.start.utf16);
  });

  test('טעינה מחדש מאמתת עוגן מקור גם כשהכותרת היא שם מקוצר', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    const raw = 'פתיחה אחרת לגמרי לפני יהוה וסיום';
    final note = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: "ה'",
      sourceSelectedText: 'יהוה',
      sourceSelectionOffset: raw.indexOf('יהוה'),
    )).single;

    expect(note.displayTitle, "ה'");
    expect(note.anchorText, 'יהוה');
    expect(
      service.noteTextMatchesLine(note, [raw], 1, 'ספר'),
      isTrue,
    );
    final reloaded = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: raw,
    )).single;
    expect(reloaded.status, PersonalNoteStatus.located);
    expect(reloaded.anchorText, 'יהוה');

    final sameTitleWithoutSource = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: "קטע אחר עם ה' בלבד",
    )).single;
    expect(sameTitleWithoutSource.status, PersonalNoteStatus.missing);
  });

  test('איתור מחדש בשורה סמוכה משתמש בעוגן המקור ולא בכותרת', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    const raw = 'פתיחה אחרת יהוה סוף';
    final note = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: "ה'",
      sourceSelectedText: 'יהוה',
      sourceSelectionOffset: raw.indexOf('יהוה'),
    )).single;

    final moved = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: "שורה ה' בלבד\nטקסט חדש עם יהוה",
    )).single;

    expect(moved.id, note.id);
    expect(moved.status, PersonalNoteStatus.located);
    expect(moved.lineNumber, 2);
  });

  test('הערה ישנה שסומנה כחסרה בגלל פיסוק חוזרת לשורה המקורית', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    const raw =
        'אחד שתים שלוש ארבע חמש שש שבע שמונה תשע רבי יוחנן, מאי דכתיב? עוד טקסט';
    final shown = removePunctuation(raw);
    final selected = shown
        .substring(shown.indexOf('רבי יוחנן'), shown.indexOf('עוד טקסט'))
        .trim();
    final note = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: selected,
    )).single;
    database.notes[note.id] = note.copyWith(
      clearAnchor: true,
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: 1,
    );

    final restored = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: raw,
    )).single;
    expect(restored.status, PersonalNoteStatus.located);
    expect(restored.lineNumber, 1);

    database.notes[note.id] = note.copyWith(
      clearAnchor: true,
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: 1,
    );
    final stillMissing = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: 'שורה אחרת בלי הביטוי המקורי',
    )).single;
    expect(stillMissing.status, PersonalNoteStatus.missing);
  });

  test(
    'הערה שאיבדה את מיקומה נשמרת ללא שורה, ומיקום מחדש מנקה את השורה הקודמת',
    () async {
      final database = _MemoryNotesDb();
      final service = PersonalNotesService(
        database: database,
        random: Random(1),
      );
      const book = 'שורה ראשונה בספר\nשורה שנייה עם רבי יוחנן';
      final note = (await service.addNote(
        bookId: 'ספר',
        bookContent: book,
        lineNumber: 2,
        content: 'הערה',
        contentPlain: 'הערה',
        contentFormat: PersonalNoteContentFormat.plain,
      )).single;

      final missing = (await service.loadNotes(
        bookId: 'ספר',
        bookContent: 'טקסט אחר לגמרי',
      )).single;
      expect(missing.status, PersonalNoteStatus.missing);
      expect(missing.lineNumber, isNull);
      expect(missing.lastKnownLineNumber, 2);
      expect(database.notes[note.id]!.lineNumber, isNull);

      database.notes[note.id] = note;
      final replaced = (await service.loadNotes(
        bookId: 'ספר',
        bookContent: 'שורה ראשונה בספר\nמשהו אחר לגמרי',
      )).single;
      expect(replaced.status, PersonalNoteStatus.missing);
      expect(replaced.lineNumber, isNull);
      expect(replaced.lastKnownLineNumber, 2);

      final moved = (await service.repositionNote(
        bookId: 'ספר',
        noteId: note.id,
        bookContent: book,
        lineNumber: 1,
      )).single;
      expect(moved.lineNumber, 1);
      expect(moved.lastKnownLineNumber, isNull);
    },
  );
}
