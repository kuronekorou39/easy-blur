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

    // Draw media (image/video frame)
    final src = Rect.fromLTWH(
      0, 0,
      mediaImage!.width.toDouble(),
      mediaImage!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(mediaImage!, src, dst, Paint());

    // Draw each visible layer's mosaic
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

    // Draw selection handle
    if (isSelected) {
      _drawSelectionBorder(canvas, rect, state, cx, cy);
    }
  }

  void _drawPixelate(Canvas canvas, Rect rect, double intensity, double scale) {
    final blockSize = max(2.0, intensity * scale * 0.5);
    final paint = Paint();

    // Simplified pixelation: draw colored blocks
    // In a real implementation, we'd sample from the media image
    // For now, fill with semi-transparent overlay to indicate mosaic area
    for (double y = rect.top; y < rect.bottom; y += blockSize) {
      for (double x = rect.left; x < rect.right; x += blockSize) {
        final bw = min(blockSize, rect.right - x);
        final bh = min(blockSize, rect.bottom - y);
        // Use a hash-based color to simulate pixelation visually
        final hash = (x ~/ blockSize * 17 + y ~/ blockSize * 31) % 255;
        paint.color = Color.fromARGB(180, hash ~/ 2, hash ~/ 2, hash ~/ 2);
        canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), paint);
      }
    }
  }

  void _drawBlur(Canvas canvas, Rect rect, double intensity, Size canvasSize) {
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

  void _drawSelectionBorder(
    Canvas canvas, Rect rect, Keyframe state, double cx, double cy,
  ) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(state.rotation);
    canvas.translate(-cx, -cy);

    final borderPaint = Paint()
      ..color = const Color(0xFF6c5ce7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(rect.inflate(2), borderPaint);

    // Corner handles
    final handlePaint = Paint()..color = Colors.white;
    const handleSize = 8.0;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ];
    for (final corner in corners) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handleSize, height: handleSize),
        handlePaint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: handleSize, height: handleSize),
        borderPaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MosaicPainter oldDelegate) {
    return oldDelegate.mediaImage != mediaImage ||
        oldDelegate.currentTime != currentTime ||
        oldDelegate.layers != layers ||
        oldDelegate.selectedLayerIndex != selectedLayerIndex;
  }
}
