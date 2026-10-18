//
// Super simple thumbnails view
//
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:otzaria/pdf_book/utils/bounded_image_cache.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:pdfrx/pdfrx.dart';

class ThumbnailsView extends StatefulWidget {
  const ThumbnailsView({
    required this.documentRef,
    required this.controller,
    this.onNavigateToPage,
    this.shownPagesFor,
    this.thumbnailCache,
    super.key,
  });

  final PdfDocumentRef? documentRef;
  final PdfViewerController? controller;

  /// ניווט של המסך (שומר זום ונעילת זוגות); בלעדיו goToPage מאפס את הזום.
  final Future<void> Function(int pageNumber)? onNavigateToPage;

  /// העמודים שמוצגים יחד עם [pageNumber] — בתצוגת ספר כל הכפולה מודגשת.
  final ({int startPage, int endPageExclusive}) Function(int pageNumber)?
  shownPagesFor;

  /// מטמון של הבעלים, שמרוקן אותו כשהטאב מוסתר; בלעדיו לתצוגה יש מטמון משלה.
  final PdfThumbnailCache? thumbnailCache;

  @override
  State<ThumbnailsView> createState() => _ThumbnailsViewState();
}

class _ThumbnailsViewState extends State<ThumbnailsView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  bool _isManuallyScrolling = false;
  int? _lastScrolledPage;
  int? _lastKnownPage;

  PdfThumbnailCache? _ownCache;

  /// פריט שנגלל מחוץ למסך נבנה מחדש בחזרה; בלי המטמון העמוד היה מרונדר שוב.
  PdfThumbnailCache get _thumbnailCache =>
      widget.thumbnailCache ?? (_ownCache ??= createPdfThumbnailCache());

  /// גובה הפריט (250) ועוד השוליים (8 מכל צד) — גם לגלילה אל העמוד הנוכחי.
  static const double _itemExtent = 266;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _lastKnownPage = _currentPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
      _scrollToActiveItem();
    });
  }

  @override
  void didUpdateWidget(covariant ThumbnailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
      _lastKnownPage = _currentPage;
    }
    if (oldWidget.documentRef != widget.documentRef) {
      _thumbnailCache.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
        _scrollToActiveItem();
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _scrollController.dispose();
    _ownCache?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final page = _currentPage;
    if (page == _lastKnownPage) return;
    _lastKnownPage = page;
    setState(() {});
    _scrollToActiveItem();
  }

  int? get _currentPage => (widget.controller?.isReady ?? false)
      ? widget.controller!.pageNumber
      : null;

  void _scrollToActiveItem() {
    if (_isManuallyScrolling || !(widget.controller?.isReady ?? false)) return;
    final currentPage = widget.controller?.pageNumber;
    if (currentPage == null || _lastScrolledPage == currentPage) return;
    if (!_scrollController.hasClients) return;

    const itemExtent = _itemExtent;
    final viewportHeight = _scrollController.position.viewportDimension;
    final target =
        itemExtent * (currentPage - 1) -
        (viewportHeight / 2) +
        (itemExtent / 2);
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    _lastScrolledPage = currentPage;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.documentRef == null) return const SizedBox.shrink();
    return PdfDocumentViewBuilder(
      documentRef: widget.documentRef!,
      builder: (context, document) => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _isManuallyScrolling = true;
          } else if (notification is ScrollEndNotification) {
            _isManuallyScrolling = false;
          }
          return false;
        },
        child: ListView.builder(
          key: const PageStorageKey('pdfThumbnails'),
          controller: _scrollController,
          itemExtent: _itemExtent,
          itemCount: document?.pages.length ?? 0,
          itemBuilder: (context, index) {
            final currentPage = _currentPage;
            final shown = currentPage == null
                ? null
                : widget.shownPagesFor?.call(currentPage) ??
                      (
                        startPage: currentPage,
                        endPageExclusive: currentPage + 1,
                      );
            final isSelected =
                shown != null &&
                index + 1 >= shown.startPage &&
                index + 1 < shown.endPageExclusive;
            return Container(
              margin: const EdgeInsets.all(8),
              height: 250,
              decoration: isSelected
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: AppTokens.borderRadiusAll,
                    )
                  : null,
              child: Column(
                children: [
                  SizedBox(
                    height: 220,
                    child: InkWell(
                      onTap: () =>
                          widget.onNavigateToPage?.call(index + 1) ??
                          widget.controller?.goToPage(
                            pageNumber: index + 1,
                            anchor: PdfPageAnchor.top,
                          ),
                      child: document == null
                          ? const SizedBox()
                          : _PageThumbnail(
                              page: document.pages[index],
                              cache: _thumbnailCache,
                            ),
                    ),
                  ),
                  Text('${index + 1}'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// עמוד שנמדד מחדש הוא אובייקט [PdfPage] חדש, ולכן תמונה ישנה לא תוחזר עבורו.
typedef PdfThumbnailCache =
    BoundedImageCache<(PdfPage page, int width, int height)>;

PdfThumbnailCache createPdfThumbnailCache() =>
    PdfThumbnailCache(maxBytes: 32 * 1024 * 1024);

typedef _ThumbnailKey = (PdfPage page, int width, int height);

class _PageThumbnail extends StatefulWidget {
  const _PageThumbnail({required this.page, required this.cache});

  final PdfPage page;
  final PdfThumbnailCache cache;

  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
  static const double _maximumDpi = 300;
  static const BoxShadow _pageShadow = BoxShadow(
    color: Colors.black54,
    blurRadius: 4,
    offset: Offset(2, 2),
  );

  ui.Image? _image;
  _ThumbnailKey? _requestedKey;
  PdfPageRenderCancellationToken? _cancellationToken;

  @override
  void dispose() {
    _cancellationToken?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final page = widget.page;
        if (page.width <= 0 || page.height <= 0) return const SizedBox();
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final scale = math.min(
          _maximumDpi / 72,
          math.min(
            constraints.maxWidth * pixelRatio / page.width,
            constraints.maxHeight * pixelRatio / page.height,
          ),
        );
        final width = (page.width * scale).round();
        final height = (page.height * scale).round();
        if (width <= 0 || height <= 0) return const SizedBox();
        _requestImage((page, width, height));

        final image = _image;
        return Align(
          child: AspectRatio(
            aspectRatio: page.width / page.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: image == null ? Colors.white : null,
                boxShadow: const [_pageShadow],
              ),
              child: image == null
                  ? null
                  : RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
        );
      },
    );
  }

  /// נקרא מתוך build: פגיעה במטמון מוצגת באותה בנייה, ורינדור מסתיים ב-setState.
  void _requestImage(_ThumbnailKey key) {
    if (key == _requestedKey) return;
    _requestedKey = key;
    _cancellationToken?.cancel();
    _cancellationToken = null;
    final cached = widget.cache.lookup(key);
    if (cached != null) {
      _image?.dispose();
      _image = cached;
      return;
    }
    _render(key);
  }

  Future<void> _render(_ThumbnailKey key) async {
    final (page, width, height) = key;
    // אחרי clear() רינדור שהתחיל קודם שייך למסמך או לטאב שכבר שוחררו.
    final generation = widget.cache.generation;
    final token = _cancellationToken = page.createCancellationToken();
    final pageImage = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      cancellationToken: token,
    );
    if (pageImage == null) return;
    try {
      final image = await pageImage.createImage();
      widget.cache.put(key, image, generation: generation);
      if (!mounted || key != _requestedKey) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (_) {
      // בלי איפוס הבקשה העמוד היה נשאר ריק עד שגודלו ישתנה.
      if (key == _requestedKey) _requestedKey = null;
    } finally {
      pageImage.dispose();
    }
  }
}
