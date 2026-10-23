import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
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
    this.crossAxisPadding = 0,
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

  /// נקרא פעם אחת לכל רוחב; ערך שתלוי ב-context נקרא ב-build ונכנס ל-[styleKey]
  /// או ל-crossAxisLayoutKey של הרשימה.
  final double Function(double availableWidth)? textWidth;
  final Object? styleKey;

  /// הריפוד האופקי של הרשימה. החימום מוערך ברוחב הפריט שבפריסה, כי בזמן שינוי
  /// רוחב ברשימה גדולה הרשימה אינה קוראת להערכה, ורוחב שנלמד ממנה מיושן.
  final double crossAxisPadding;
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
  double _layoutItemWidth = 0;
  double _itemWidth = 0;
  double? _textWidth;

  @override
  void initState() {
    super.initState();
    DeveloperDiagnostics.instance.trackEstimateRefreshes(widget.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    DeveloperDiagnostics.instance.untrackEstimateRefreshes(widget.controller);
    _data?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReadingExtentEstimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _textWidth = null;
    final changedReader =
        oldWidget.segments.readerIdentity != widget.segments.readerIdentity;
    if (changedReader) {
      _data?.dispose();
      _data = null;
      _refreshScheduled = false;
    } else {
      _data?.update(widget.segments);
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      DeveloperDiagnostics.instance
        ..untrackEstimateRefreshes(oldWidget.controller)
        ..trackEstimateRefreshes(widget.controller);
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
              for (final item in items) item: _estimate(item, _layoutItemWidth),
            }),
          );
        }
      }
    });
  }

  double _estimate(int index, double width) {
    var textWidth = _textWidth;
    if (textWidth == null || width != _itemWidth) {
      _itemWidth = width;
      final resolved = widget.textWidth?.call(width);
      textWidth = _textWidth = resolved != null && resolved > 0
          ? resolved
          : width;
    }
    return _estimates.estimate(index, textWidth, _metrics!);
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
        _layoutItemWidth = math.max(
          0.0,
          constraints.maxWidth - widget.crossAxisPadding,
        );
        return widget.builder(_estimate, _estimationKey);
      },
    );
  }
}
