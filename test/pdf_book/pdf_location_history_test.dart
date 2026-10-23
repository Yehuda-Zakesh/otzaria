import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  setUp(() => Settings.init(cacheProvider: MemorySettingsCache()));

  test('עוגן שומר מיקום בתוך העמוד וזום גם לאחר שינוי פריסה וגודל חלון', () {
    final controller = _Controller();
    final location = PdfReadingLocation.capture(controller)!;
    expect(location.pageNumber, 2);
    expect(location.pageOffset, const Offset(25, 120));
    expect(location.zoom, 2);
    expect(
      location.centerIn(
        const Rect.fromLTWH(700, 1000, 600, 800),
        const Size(1000, 600),
      ),
      const Offset(975, 1270),
    );
  });

  test('היסטוריה מוגבלת ל־50 קפיצות ומסירה רק כפילות רצופה', () {
    final history = PdfLocationHistory();
    for (var page = 1; page <= 60; page++) {
      final location = PdfReadingLocation(
        pageNumber: page,
        pageOffset: Offset.zero,
        zoom: 1,
      );
      history.remember(location);
      history.remember(location);
    }
    final pages = <int>[];
    while (history.canGoBack) {
      pages.add(history.takePrevious()!.pageNumber);
    }
    expect(pages, List.generate(50, (i) => 60 - i));
    expect(history.takePrevious(), isNull);
  });

  test(
    'גלילה רגילה אינה מוסיפה נקודת חזרה; זכירה ושחזור מתבצעים דרך אירועים מפורשים',
    () async {
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר', path: '/book.pdf'),
        pageNumber: 2,
      );
      final controller = _Controller();
      tab.pdfViewerController = controller;
      final bloc = PdfBookBloc(
        tab: tab,
        initialState: PdfBookInitial(book: tab.book, initialPageNumber: 2),
        pdfrxInit: () async {},
      );
      addTearDown(bloc.close);
      addTearDown(tab.dispose);
      // ignore: invalid_use_of_visible_for_testing_member
      bloc.emit(
        PdfBookLoaded(
          book: tab.book,
          currentPageNumber: 2,
          totalPages: 2,
          isLoading: false,
        ),
      );
      final moved = bloc.stream.first;
      bloc.add(const UpdatePageNumber(pageNumber: 1));
      await moved;
      expect(tab.navigationHistory.canGoBack, isFalse);
      final saved = PdfReadingLocation.capture(controller)!;
      final remembered = bloc.stream.first;
      bloc.add(RememberPdfLocation(saved));
      await remembered;
      expect((bloc.state as PdfBookLoaded).canReturnToLocation, isTrue);
      final returned = bloc.stream.first;
      bloc.add(const ReturnToPreviousPdfLocation());
      await returned;
      await pumpEventQueue();
      expect(controller.lastCenter, const Offset(225, 1080));
      expect(controller.lastZoom, 2);
      expect(controller.lastDuration, Duration.zero);
      expect(tab.navigationHistory.canGoBack, isFalse);
      expect((bloc.state as PdfBookLoaded).canReturnToLocation, isFalse);
    },
  );
}

class _Controller extends PdfViewerController {
  Offset? lastCenter;
  double? lastZoom;
  Duration? lastDuration;

  @override
  bool get isReady => true;
  @override
  int? get pageNumber => 2;
  @override
  double get currentZoom => 2;
  @override
  Rect get visibleRect => const Rect.fromLTWH(25, 930, 400, 300);
  @override
  Size get viewSize => const Size(800, 600);
  @override
  PdfPageLayout get layout => PdfPageLayout(
    pageLayouts: [
      Rect.fromLTWH(0, 0, 600, 800),
      Rect.fromLTWH(0, 810, 600, 800),
    ],
    documentSize: Size(600, 1610),
  );
  @override
  Matrix4 calcMatrixFor(Offset position, {double? zoom, Size? viewSize}) {
    lastCenter = position;
    lastZoom = zoom;
    return Matrix4.identity();
  }

  @override
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    lastDuration = duration;
  }
}
