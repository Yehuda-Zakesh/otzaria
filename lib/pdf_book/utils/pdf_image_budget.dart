import 'package:pdfrx/pdfrx.dart';

/// אומדן משותף לתמונות PDF, חוצצי רינדור והמרה בחלון הנוכחי.
/// שמונה בתים לפיקסל שמור מייצגים יחד את התמונה ומשאב ה-GPU המשוער.
const kPdfSharedImageBudgetBytes = 96 * 1024 * 1024;

/// תקציב הרינדור המקומי של תצוגת הספר המקדימה בספרייה.
const kPdfPreviewImageBudgetBytes = 16 * 1024 * 1024;

final pdfSharedImageBudget = PdfImageCacheBudget(
  maximumBytes: kPdfSharedImageBudgetBytes,
);
