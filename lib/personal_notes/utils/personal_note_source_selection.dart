import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

({String text, int offset})? mapPersonalNoteSourceSelection({
  required String bookId,
  required int lineIndex,
  required String rawLine,
  required RenderSettings settings,
  required String selectedText,
  int? startHint,
}) {
  final selection = const ReaderSelectionService().buildFromRenderedSelection(
    bookId: bookId,
    bookTitle: bookId,
    sectionIndex: lineIndex,
    rawText: rawLine,
    settings: settings,
    selectedText: selectedText,
    startHint: startHint,
  );
  if (selection == null) return null;
  return (
    text: selection.sourceSelectedText,
    offset: selection.sourceRange.start.utf16,
  );
}
