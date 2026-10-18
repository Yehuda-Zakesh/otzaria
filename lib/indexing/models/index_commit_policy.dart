/// commit באמצע ריצה (נקודת שמירה מפני קריסה): לפי מסמכים שנצברו או זמן.
/// מספר ספרים אינו מדד — ספר אחד עשוי להיות גדול מאלף אחרים.
class IndexCommitPolicy {
  IndexCommitPolicy({
    this.maxDocs = defaultMaxDocs,
    this.maxInterval = defaultMaxInterval,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _lastCommit = _clock();
  }

  static const int defaultMaxDocs = 2000000;
  static const Duration defaultMaxInterval = Duration(seconds: 90);

  final int maxDocs;
  final Duration maxInterval;
  final DateTime Function() _clock;
  late DateTime _lastCommit;
  int _books = 0;
  int _docs = 0;

  /// ספרים שנכתבו מאז ה-commit האחרון (כולל סמנים ריקים).
  int get pendingBooks => _books;

  int get pendingDocs => _docs;

  void recordBook({int docs = 0}) {
    _books++;
    _docs += docs;
  }

  bool get isDue =>
      _books > 0 &&
      (_docs >= maxDocs || _clock().difference(_lastCommit) >= maxInterval);

  void committed() {
    _books = 0;
    _docs = 0;
    _lastCommit = _clock();
  }
}

/// ספרים לקריאת `addLibraryBooks` אחת: כ-[target] של עבודה. אצווה ארוכה
/// מעכבת את ה-commit, את דיווח ההתקדמות ואת החלפת ה-writer במצב חסכוני.
class LibraryBatchSizer {
  LibraryBatchSizer({
    this.target = const Duration(seconds: 2),
    this.minBooks = 8,
    this.maxBooks = 256,
    int initialBooks = 16,
  }) : _size = initialBooks;

  final Duration target;
  final int minBooks;
  final int maxBooks;
  int _size;

  int get size => _size;

  /// [books] נוספו ב-[elapsed]; אצווה שבוטלה באמצע אינה מדגימה את הקצב.
  void recordBatch(int books, Duration elapsed) {
    if (books <= 0) return;
    final micros = elapsed.inMicroseconds;
    final next = micros <= 0
        ? maxBooks
        : (books * target.inMicroseconds / micros).round();
    _size = next.clamp(minBooks, maxBooks);
  }
}
