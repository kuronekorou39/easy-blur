import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/models.dart';

class MosaicPainter extends CustomPainter {
  final ui.Image? mediaImage;
  final List<MosaicLayer> layers;
  final Duration currentTime;
  final Size mediaSize;
  final int? selectedLayerIndex;

  MosaicPainter({
    required this.mediaImage,
    required this.layers,
    required this.currentTime,
    required this.mediaSize,
    this.selectedLayerIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mediaImage == null) return;

    final src = Rect.fromLTWH(
      0, 0,
      mediaImage!.width.toDouble(),
      mediaImage!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(mediaImage!, src, dst, Paint());

    final scaleX = size.width / mediaSize.width;
    final scaleY = size.height / mediaSize.height;

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.visible || layer.keyframes.isEmpty) continue;

      final state = layer.getStateAt(currentTime);
      _drawMosaicRegion(
        canvas,
        size,
        layer,
        state,
        scaleX,
        scaleY,
        isSelected: i == selectedLayerIndex,
      );
    }
  }

  void _drawMosaicRegion(
    Canvas canvas,
    Size canvasSize,
    MosaicLayer layer,
    Keyframe state,
    double scaleX,
    double scaleY, {
    bool isSelected = false,
  }) {
    final cx = state.position.dx * scaleX;
    final cy = state.position.dy * scaleY;
    final w = state.size.width * scaleX;
    final h = state.size.height * scaleY;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(state.rotation);
    canvas.translate(-cx, -cy);

    // Clip to shape
    final path = Path();
    if (layer.shape == MosaicShape.ellipse) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    }
    canvas.clipPath(path);

    // Draw mosaic effect
    switch (layer.type) {
      case MosaicType.pixelate:
        _drawPixelate(canvas, rect, state.intensity, scaleX);
        break;
      case MosaicType.blur:
        _drawBlur(canvas, rect, state.intensity, canvasSize);
        break;
      case MosaicType.blackout:
        canvas.drawRect(rect, Paint()..color = Colors.black);
        break;
    }

    canvas.restore();

    if (isSelected) {
      _drawSelection(canvas, rect, state, cx, cy);
    }
  }

  void _drawPixelate(
      Canvas canvas, Rect rect, double intensity, double scale) {
    final blockSize = max(2.0, intensity * scale * 0.5);
    final paint = Paint();

    for (double y = rect.top; y < rect.bottom; y += blockSize) {
      for (double x = rect.left; x < rect.right; x += blockSize) {
        final bw = min(blockSize, rect.right - x);
        final bh = min(blockSize, rect.bottom - y);
        final hash = (x ~/ blockSize * 17 + y ~/ blockSize * 31) % 255;
        paint.color = Color.fromARGB(180, hash ~/ 2, hash ~/ 2, hash ~/ 2);
        canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), paint);
      }
    }
  }

  void _drawBlur(
      Canvas canvas, Rect rect, double intensity, Size canvasSize) {
    final sigma = max(1.0, intensity * 0.8);
    final paint = Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    canvas.saveLayer(rect, paint);
    if (mediaImage != null) {
      final src = Rect.fromLTWH(
        0, 0,
        mediaImage!.width.toDouble(),
        mediaImage!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
      canvas.drawImageRect(mediaImage!, src, dst, Paint());
    }
    canvas.restore();
  }

  void _drawSelection(
    Canvas canvas,
    Rect rect,
    Keyframe state,
    double cx,
    double cy,
  ) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(state.rotation);
    canvas.translate(-cx, -cy);

    const accentColor = Color(0xFF6c5ce7);

    // Dashed border
    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final inflated = rect.inflate(2);
    _drawDashedRect(canvas, inflated, borderPaint, dashLength: 6, gapLength: 4);

    // Corner handles (larger, rounded)
    const handleRadius = 7.0;
    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final corners = [
      inflated.topLeft,
      inflated.topRight,
      inflated.bottomLeft,
      inflated.bottomRight,
    ];
    for (final corner in corners) {
      canvas.drawCircle(corner, handleRadius, handleFill);
      canvas.drawCircle(corner, handleRadius, handleStroke);
    }

    // Edge midpoint handles (smaller)
    const edgeRadius = 4.0;
    final edges = [
      Offset(inflated.center.dx, inflated.top),
      Offset(inflated.center.dx, inflated.bottom),
      Offset(inflated.left, inflated.center.dy),
      Offset(inflated.right, inflated.center.dy),
    ];
    for (final edge in edges) {
      canvas.drawCircle(edge, edgeRadius, handleFill);
      canvas.drawCircle(edge, edgeRadius, handleStroke);
    }

    // Rotation handle (top center, connected by line)
    final rotateAnchor = Offset(inflated.center.dx, inflated.top);
    final rotateHandle =
        Offset(inflated.center.dx, inflated.top - 30);

    canvas.drawLine(
      rotateAnchor,
      rotateHandle,
      Paint()
        ..color = accentColor.withAlpha(150)
        ..strokeWidth = 1.5,
    );

    canvas.drawCircle(rotateHandle, 8, handleFill);
    canvas.drawCircle(rotateHandle, 8, handleStroke);

    // Rotation icon inside handle
    final iconPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final iconCenter = rotateHandle;
    const iconR = 4.0;
    final iconRect =
        Rect.fromCircle(center: iconCenter, radius: iconR);
    canvas.drawArc(iconRect, -pi / 2, pi * 1.4, false, iconPaint);
    // Arrow tip
    final arrowEnd = Offset(
      iconCenter.dx + iconR * cos(-pi / 2 + pi * 1.4),
      iconCenter.dy + iconR * sin(-pi / 2 + pi * 1.4),
    );
    final arrowDir = pi * 1.4 - pi / 2 + pi / 2;
    canvas.drawLine(
      arrowEnd,
      Offset(arrowEnd.dx + 3 * cos(arrowDir - 0.6),
          arrowEnd.dy + 3 * sin(arrowDir - 0.6)),
      iconPaint,
    );

    canvas.restore();
  }

  void _drawDashedRect(
      Canvas canvas, Rect rect, Paint paint,
      {double dashLength = 6, double gapLength = 4}) {
    final totalDash = dashLength + gapLength;
    // Top
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, totalDash,
        dashLength);
    // Right
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint,
        totalDash, dashLength);
    // Bottom
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint,
        totalDash, dashLength);
    // Left
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint,
        totalDash, dashLength);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint,
      double totalDash, double dashLength) {
    final delta = end - start;
    final length = delta.distance;
    final dir = Offset(delta.dx / length, delta.dy / length);
    double drawn = 0;
    while (drawn < length) {
      final segEnd = min(drawn + dashLength, length);
      canvas.drawLine(
        Offset(start.dx + dir.dx * drawn, start.dy + dir.dy * drawn),
        Offset(start.dx + dir.dx * segEnd, start.dy + dir.dy * segEnd),
        paint,
      );
      drawn += totalDash;
    }
  }

  @override
  bool shouldRepaint(covariant MosaicPainter oldDelegate) {
    return oldDelegate.mediaImage != mediaImage ||
        oldDelegate.currentTime != currentTime ||
        oldDelegate.layers != layers ||
        oldDelegate.selectedLayerIndex != selectedLayerIndex;
  }
}
