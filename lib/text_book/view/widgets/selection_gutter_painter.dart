import 'package:flutter/material.dart';

/// Paints the selected paragraph marker without affecting text layout or taps.
class SelectionGutterPainter extends CustomPainter {
  const SelectionGutterPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const width = 3.0;
    final rect = Rect.fromLTWH(size.width - width, 0, width, size.height);
    canvas.drawRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant SelectionGutterPainter oldDelegate) =>
      oldDelegate.color != color;

  @override
  bool? hitTest(Offset position) => false;
}
