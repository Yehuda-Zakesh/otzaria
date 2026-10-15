import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_notes_export_dialog.dart';

import '../../test_helpers/dst_days.dart';

PersonalNote _note(String id, DateTime updatedAt) => PersonalNote(
  id: id,
  bookId: 'ספר',
  lineNumber: 1,
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: id,
  contentPlain: id,
  contentFormat: PersonalNoteContentFormat.quillDelta,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

String _typed(DateTime d) => '${d.month}/${d.day}/${d.year}';

void main() {
  group('Date range ending on a DST day', skip: noDstSkipReason, () {
    for (final hours in [23, 25]) {
      testWidgets('$hours-hour day keeps exactly its notes', (tester) async {
        final day = localDayLasting(hours)!;
        NotesExportSelection? selection;
        await tester.binding.setSurfaceSize(const Size(1200, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => selection = await showDialog(
                  context: context,
                  builder: (_) => PersonalNotesExportDialog(
                    allNotes: [
                      _note('late', atHour(day, 23, 30)),
                      _note('next', atHour(plusDays(day, 1), 0, 30)),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('טווח זמן'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('בחר טווח תאריכים'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Switch to input'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), _typed(day));
        await tester.enterText(fields.at(1), _typed(day));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ייצא'));
        await tester.pumpAndSettle();

        expect(selection!.notes.map((n) => n.id), ['late']);
      });
    }
  });
}
