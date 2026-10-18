import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';

class _UnusedRepository implements PersonalNotesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  blocTest<PersonalNotesBloc, PersonalNotesState>(
    'בחירה חדשה בלי מיפוי מקור מנקה את מיפוי הבחירה הקודמת',
    build: () => PersonalNotesBloc(repository: _UnusedRepository()),
    act: (bloc) {
      bloc.add(
        const StartCreatingPersonalNote(
          bookId: 'ספר',
          lineNumber: 1,
          selectedText: 'יקוק',
          sourceSelectedText: 'יהוה',
          sourceSelectionOffset: 12,
        ),
      );
      bloc.add(
        const StartCreatingPersonalNote(
          bookId: 'ספר',
          lineNumber: 2,
          selectedText: 'בחירה חוצת שורות',
        ),
      );
    },
    expect: () => [
      isA<PersonalNotesState>()
          .having(
            (state) => state.newNoteSourceSelectedText,
            'source text',
            'יהוה',
          )
          .having(
            (state) => state.newNoteSourceSelectionOffset,
            'source offset',
            12,
          ),
      isA<PersonalNotesState>()
          .having(
            (state) => state.newNoteSelectedText,
            'visible selection',
            'בחירה חוצת שורות',
          )
          .having(
            (state) => state.newNoteSourceSelectedText,
            'source text cleared',
            isNull,
          )
          .having(
            (state) => state.newNoteSourceSelectionOffset,
            'source offset cleared',
            isNull,
          ),
    ],
  );

  blocTest<PersonalNotesBloc, PersonalNotesState>(
    'מצב הפיסוק נשמר עם הבחירה עד לשמירת ההערה ומתאפס בביטול',
    build: () => PersonalNotesBloc(repository: _UnusedRepository()),
    act: (bloc) {
      bloc.add(
        const StartCreatingPersonalNote(
          bookId: 'ספר',
          lineNumber: 1,
          selectedText: 'מילה',
          selectionColumn: 7,
          punctuationHidden: true,
        ),
      );
      bloc.add(const CancelCreatingPersonalNote());
    },
    expect: () => [
      isA<PersonalNotesState>().having(
        (state) => state.newNotePunctuationHidden,
        'פיסוק מוסתר בזמן עריכה',
        isTrue,
      ),
      isA<PersonalNotesState>().having(
        (state) => state.newNotePunctuationHidden,
        'פיסוק מוצג אחרי ביטול',
        isFalse,
      ),
    ],
  );
}
