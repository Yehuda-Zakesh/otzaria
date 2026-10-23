import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:pdfrx/pdfrx.dart';

/// עוגן קריאה בתוך עמוד, שאינו תלוי בגודל החלון או במיקום העמוד בפריסה.
class PdfReadingLocation extends Equatable {
  const PdfReadingLocation({
    required this.pageNumber,
    required this.pageOffset,
    required this.zoom,
  });

  final int pageNumber;
  final Offset pageOffset;
  final double zoom;

  static PdfReadingLocation? capture(PdfViewerController controller) {
    if (!controller.isReady) return null;
    final number = controller.pageNumber;
    final pages = controller.layout.pageLayouts;
    if (number == null || number < 1 || number > pages.length) return null;
    return PdfReadingLocation(
      pageNumber: number,
      pageOffset: controller.visibleRect.topLeft - pages[number - 1].topLeft,
      zoom: controller.currentZoom,
    );
  }

  Offset centerIn(Rect page, Size viewSize) =>
      page.topLeft +
      pageOffset +
      Offset(viewSize.width / zoom / 2, viewSize.height / zoom / 2);

  @override
  List<Object> get props => [pageNumber, pageOffset, zoom];
}

/// היסטוריית קפיצות זמנית של טאב; אינה מחזיקה מסמכים או תמונות.
class PdfLocationHistory {
  final _locations = <PdfReadingLocation>[];

  bool get canGoBack => _locations.isNotEmpty;
  PdfReadingLocation? get last => _locations.lastOrNull;

  void remember(PdfReadingLocation location) {
    if (last == location) return;
    _locations.add(location);
    if (_locations.length > 50) _locations.removeAt(0);
  }

  PdfReadingLocation? takePrevious() =>
      _locations.isEmpty ? null : _locations.removeLast();
}
