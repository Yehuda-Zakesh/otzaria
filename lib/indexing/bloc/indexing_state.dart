import 'package:equatable/equatable.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';

sealed class IndexingState extends Equatable {
  final int? booksProcessed;
  final int? totalBooks;
  final bool isCreatingIndex;

  const IndexingState({
    this.booksProcessed,
    this.totalBooks,
    this.isCreatingIndex = false,
  });

  @override
  List<Object?> get props => [booksProcessed, totalBooks, isCreatingIndex];
}

class IndexingInitial extends IndexingState {}

class IndexingInProgress extends IndexingState {
  const IndexingInProgress({
    super.booksProcessed,
    super.totalBooks,
    super.isCreatingIndex,
    this.isScanning = false,
    this.isPaused = false,
    this.isEconomy = false,
    this.isFinalizing = false,
  });

  /// שלב הבדיקה של ריצת אינדוקס — אילו ספרים מאונדקסים התיישנו.
  /// שלב ארוך, ולכן מוצג בחיווי (issue #1056).
  final bool isScanning;

  /// האינדוקס מושהה — הלולאה ממתינה לפני הספר הבא.
  final bool isPaused;

  /// מצב חסכוני פעיל — הכנת הספרים והכתיבה מוגבלות במשאבים.
  final bool isEconomy;

  /// כל הספרים אונדקסו והמנוע מאחד את קבצי האינדקס (commit ו-optimize).
  /// אין לשלב זה התקדמות מדידה, ולכן המונה מוחלף בהודעה נפרדת.
  final bool isFinalizing;

  @override
  List<Object?> get props => [
    ...super.props,
    isScanning,
    isPaused,
    isEconomy,
    isFinalizing,
  ];
}

class IndexingComplete extends IndexingState {
  const IndexingComplete({this.failures = const []});

  final List<IndexingFailure> failures;

  bool get isClean => failures.isEmpty;
  int get failureCount => failures.length;

  /// כשלים שמנעו אינדוקס של ספר; אזהרה (PDF שחלק מעמודיו נשמטו) אינה נספרת.
  int get blockingFailureCount =>
      failures.where((failure) => failure.preventedIndexing).length;

  int get warningCount => failureCount - blockingFailureCount;

  @override
  List<Object?> get props => [failures];
}

class IndexingStopped extends IndexingState {}

class IndexingError extends IndexingState {
  final String error;

  const IndexingError(this.error, {super.booksProcessed, super.totalBooks});

  @override
  List<Object?> get props => [error, booksProcessed, totalBooks];
}
