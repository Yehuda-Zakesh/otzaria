import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

class _MemoryNotesDb implements PersonalNotesDatabase {
  final notes = <String, PersonalNote>{};

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async =>
      notes.values.where((note) => note.bookId == bookId).toList();

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> changed) async {
    for (final note in changed) {
      notes[note.id] = note;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PersonalNote _note(String id, int line) => PersonalNote(
  id: id,
  bookId: 'ספר',
  lineNumber: line,
  displayTitle: 'שורה $line',
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: 'הערה',
  contentPlain: 'הערה',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<int> _fastestMicros(Future<void> Function() run) async {
  var best = 1 << 62;
  for (var i = 0; i < 5; i++) {
    final stopwatch = Stopwatch()..start();
    await run();
    if (stopwatch.elapsedMicroseconds < best) {
      best = stopwatch.elapsedMicroseconds;
    }
  }
  return best;
}

void main() {
  test('ספר בלי הערות אינו מפוצל לשורות בטעינה (perf)', () async {
    // בגודל ספר גדול (כ-18 מיליון תווים בערוך השולחן); כאן 6 מיליון.
    final content = List.filled(
      200000,
      'שורה בספר עם כמה מילים לבדיקה',
    ).join('\n');
    final service = PersonalNotesService(database: _MemoryNotesDb());

    final split = await _fastestMicros(
      () async => splitBookContentIntoLines(content),
    );
    final load = await _fastestMicros(
      () => service.loadNotes(bookId: 'ספר', bookContent: content),
    );

    expect(load, lessThan(split ~/ 4), reason: 'split=$splitµs load=$loadµs');
  });

  test('ספר בלי הערות מחזיר רשימה ריקה; עם הערות היישוב לא השתנה', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database);
    const content = 'שורה 1\nשורה 2\nשורה 3';

    final empty = await service.loadNotes(bookId: 'ספר', bookContent: content);
    expect(empty, isEmpty);
    empty.add(_note('x', 1));

    database.notes['a'] = _note('a', 3);
    database.notes['b'] = _note('b', 9);
    final notes = await service.loadNotes(bookId: 'ספר', bookContent: content);

    expect(notes.map((note) => note.id), ['a', 'b']);
    expect(notes.first.status, PersonalNoteStatus.located);
    expect(notes.last.status, PersonalNoteStatus.missing);
    expect(notes.last.lastKnownLineNumber, 9);
  });
}
