import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_extent_estimates.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// מחברת שינויים בתוכן להערכות הרשימה בלי לאפס מדידות בכל חימום.
class ReadingExtentEstimation extends StatefulWidget {
  const ReadingExtentEstimation({
    super.key,
    required this.segments,
    required this.controller,
    required this.fontSize,
    required this.builder,
    this.lineHeight = 1.5,
    this.fontFamily,
    this.fontWeight,
    this.fontVariations,
    this.contentWidthRatio = 1,
    this.verticalPadding = 4,
    this.textWidth,
    this.styleKey,
  });

  final ReadingSegments segments;
  final ItemScrollController controller;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final List<FontVariation>? fontVariations;
  final double contentWidthRatio;
  final double verticalPadding;
  final double Function(double availableWidth)? textWidth;
  final Object? styleKey;
  final Widget Function(ItemExtentEstimator estimator, Object estimationKey)
  builder;

  @override
  State<ReadingExtentEstimation> createState() =>
      _ReadingExtentEstimationState();
}

class _ReadingExtentEstimationState extends State<ReadingExtentEstimation> {
  ReadingExtentEstimates? _data;
  ReadingExtentEstimates get _estimates =>
      _data ??= ReadingExtentEstimates(widget.segments);
  ReadingExtentMetrics? _metrics;
  Object? _metricStyle;
  Object _estimationKey = Object();
  bool _refreshScheduled = false;
  bool _enabled = true;
  double _availableWidth = 0;
  double _itemWidth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _data?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReadingExtentEstimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedReader =
        oldWidget.segments.readerIdentity != widget.segments.readerIdentity;
    if (changedReader) {
      _data?.dispose();
      _data = null;
      _refreshScheduled = false;
    } else {
      _data?.update(widget.segments);
    }
    if (changedReader ||
        !oldWidget.segments.layout.hasSameStructure(widget.segments.layout) ||
        !identical(oldWidget.controller, widget.controller)) {
      _estimationKey = Object();
    }
  }

  void _scheduleRefresh() {
    if (!_enabled || _refreshScheduled) return;
    final data = _estimates;
    if (!data.needsRefresh) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(_data, data)) return;
      if (!_enabled) {
        _refreshScheduled = false;
        return;
      }
      final changes = await data.refresh(
        shouldContinue: () => mounted && _enabled,
      );
      if (!mounted || !identical(_data, data)) return;
      _refreshScheduled = false;
      if (!_enabled) {
        _estimationKey = Object();
        return;
      }
      if (changes.full) {
        setState(() => _estimationKey = Object());
      } else if (changes.ranges.isNotEmpty && widget.controller.isAttached) {
        final layout = widget.segments.layout;
        final items = <int>{};
        var refreshAll = false;
        for (final range in changes.ranges) {
          final first = layout.itemForLine(range.first);
          final last = layout.itemForLine(range.last);
          if (last - first + 1 > 10000) {
            refreshAll = true;
            break;
          }
          for (var item = first; item <= last; item++) {
            items.add(item);
            if (items.length > 10000) {
              refreshAll = true;
              break;
            }
          }
          if (refreshAll) break;
        }
        if (refreshAll) {
          setState(() => _estimationKey = Object());
        } else {
          unawaited(
            widget.controller.updateEstimatedExtents({
              for (final item in items)
                item: _estimate(
                  item,
                  _itemWidth > 0 ? _itemWidth : _availableWidth,
                ),
            }),
          );
        }
      }
    });
  }

  double _estimate(int index, double width) {
    _itemWidth = width;
    final textWidth = widget.textWidth?.call(width);
    return _estimates.estimate(
      index,
      textWidth != null && textWidth > 0 ? textWidth : width,
      _metrics!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = (
      widget.fontSize,
      widget.lineHeight,
      widget.fontFamily,
      widget.fontWeight,
      Object.hashAll(
        widget.fontVariations?.map((v) => (v.axis, v.value)) ?? const [],
      ),
      widget.contentWidthRatio,
      widget.verticalPadding,
      widget.styleKey,
      scaler,
    );
    if (_metricStyle != style) {
      const sample = 'בראשית ברא אלהים את השמים ואת הארץ';
      final painter = TextPainter(
        text: TextSpan(
          text: sample,
          style: TextStyle(
            fontSize: widget.fontSize,
            height: widget.lineHeight,
            fontFamily: widget.fontFamily,
            fontWeight: widget.fontWeight,
            fontVariations: widget.fontVariations,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      _metrics = ReadingExtentMetrics(
        lineExtent: painter.height,
        charWidth: painter.width / sample.length,
        contentWidthRatio: widget.contentWidthRatio,
        verticalPadding: widget.verticalPadding,
      );
      painter.dispose();
      _metricStyle = style;
      _estimationKey = Object();
    }
    _scheduleRefresh();
    return LayoutBuilder(
      builder: (_, constraints) {
        _availableWidth = constraints.maxWidth;
        return widget.builder(_estimate, _estimationKey);
      },
    );
  }
}
