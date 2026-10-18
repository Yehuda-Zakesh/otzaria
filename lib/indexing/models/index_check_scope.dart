import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';

/// היקף שלב הבדיקה שלפני ריצת אינדוקס: אילו ספרים מאונדקסים להשוות מול
/// מקורם כדי לגלות שהתיישנו.
class IndexCheckScope extends Equatable {
  const IndexCheckScope._({required this.wholeLibrary, this.books = const []});

  /// בלי שלב בדיקה.
  static const none = IndexCheckScope._(wholeLibrary: false);

  /// כל ספרי הספרייה — כשאיש לא דיווח מה השתנה (הורדה מלאה וכד').
  static const library = IndexCheckScope._(wholeLibrary: true);

  /// רק [books] — למשל ספרי מסד מצורף שהקובץ שלו הוחלף.
  const IndexCheckScope.books(List<Book> books)
    : this._(wholeLibrary: false, books: books);

  final bool wholeLibrary;
  final List<Book> books;

  bool get isNone => !wholeLibrary && books.isEmpty;

  @override
  List<Object?> get props => [wholeLibrary, books];
}
