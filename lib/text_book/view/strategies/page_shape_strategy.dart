import 'package:flutter/material.dart';
import 'package:otzaria/text_book/view/strategies/text_book_view_strategy.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';

/// Strategy implementation for page shape view mode
///
/// Shows the traditional Talmud page layout with commentaries
/// positioned around the main text
class PageShapeStrategyImpl extends TextBookViewStrategy {
  @override
  Widget buildView(BuildContext context, TextBookViewConfig config) {
    final page = PageShapeScreen(
      key: config.pageShapeKey,
      openBookCallback: config.openBookCallback,
      sidebarTabNotifier: config.pageShapeSidebarTabNotifier,
      openSettingsNotifier: config.pageShapeOpenSettingsNotifier,
      onOpenSearch: config.openSearch,
      tab: config.tab,
    );

    // Wrap with RepaintBoundary if print key is provided
    final boundaryKey = config.pageShapePrintBoundaryKey;
    if (boundaryKey == null) return page;

    return RepaintBoundary(
      key: boundaryKey,
      child: page,
    );
  }
}
