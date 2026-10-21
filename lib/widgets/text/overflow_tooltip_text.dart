import 'package:flutter/material.dart';

/// בודק האם הטקסט גולש מעבר למספר השורות המרבי ברוחב הנתון.
bool textOverflows({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
  TextAlign textAlign = TextAlign.start,
  TextDirection? textDirection,
}) {
  final direction = textDirection ?? Directionality.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  final key = (
    text,
    style,
    maxLines,
    maxWidth,
    textAlign,
    direction,
    textScaler,
  );
  final cached = _overflowCache.remove(key);
  if (cached != null) return _overflowCache[key] = cached;
  debugTextOverflowLayouts++;
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: textAlign,
    textDirection: direction,
    maxLines: maxLines,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final overflows = textPainter.didExceedMaxLines;
  textPainter.dispose();
  if (_overflowCache.length >= 2000) {
    _overflowCache.remove(_overflowCache.keys.first);
  }
  return _overflowCache[key] = overflows;
}

// שורות עץ הניווט נבנות מחדש בכל גלילה ומודדות שוב אותו טקסט; גופן שנטען משנה מדידה.
final Map<Object, bool> _overflowCache = () {
  final cache = <Object, bool>{};
  PaintingBinding.instance.systemFonts.addListener(cache.clear);
  return cache;
}();

@visibleForTesting
int debugTextOverflowLayouts = 0;

/// ווידג'ט טקסט שעוטף את עצמו ב-[Tooltip] אך ורק כאשר הטקסט נקטע ([TextOverflow.ellipsis]).
///
/// כשהטקסט נכנס במלואו במגבלות הרוחב, מרונדר [Text] רגיל ללא תקורה או טולטיפ מיותר.
class OverflowTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  final String? tooltipMessage;
  final Duration waitDuration;

  const OverflowTooltipText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.tooltipMessage,
    this.waitDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow =
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            textOverflows(
              context: context,
              text: text,
              style: resolvedStyle,
              maxLines: maxLines,
              maxWidth: constraints.maxWidth,
              textAlign: textAlign,
            );

        final child = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: resolvedStyle,
        );

        if (!hasOverflow) {
          return child;
        }

        return Tooltip(
          message: tooltipMessage ?? text,
          waitDuration: waitDuration,
          child: child,
        );
      },
    );
  }
}
