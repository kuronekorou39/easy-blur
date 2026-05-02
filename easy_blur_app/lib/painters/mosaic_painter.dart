import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/shape_paths.dart';

/// 画像レイヤー上にモザイクを描画するペインター
/// キャンバスサイズに合わせてアスペクト比を保持して画像を中央描画する
class MosaicPainter extends CustomPainter {
  final ui.Image? mediaImage;
  final List<MosaicLayer> layers;
  final Duration currentTime;
  final Size mediaSize;
  final int? selectedLayerIndex;
  final bool isPreview;

  MosaicPainter({
    required this.mediaImage,
    required this.layers,
    required this.currentTime,
    required this.mediaSize,
    this.selectedLayerIndex,
    this.isPreview = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mediaImage == null || mediaSize.isEmpty) return;

    // BoxFit.contain 相当の描画領域を計算
    final scale = _fitScale(size);
    final imgW = mediaSize.width * scale;
    final imgH = mediaSize.height * scale;
    final left = (size.width - imgW) / 2;
    final top = (size.height - imgH) / 2;
    final dst = Rect.fromLTWH(left, top, imgW, imgH);

    // 画像の周囲に微かな影を描画（プレビューの奥行き感、保存時はスキップ）
    if (isPreview) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawRect(dst.inflate(2), shadowPaint);
    }

    final src = Rect.fromLTWH(
      0,
      0,
      mediaImage!.width.toDouble(),
      mediaImage!.height.toDouble(),
    );
    canvas.drawImageRect(mediaImage!, src, dst, Paint());

    // 画像外へのクリップ（モザイクが画像領域外へはみ出さないように）
    canvas.save();
    canvas.clipRect(dst);

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.visible || layer.keyframes.isEmpty) continue;

      final state = layer.getStateAt(currentTime);
      _drawMosaicRegion(
        canvas,
        dst,
        scale,
        layer,
        state,
        isSelected: i == selectedLayerIndex,
      );
    }

    canvas.restore();

    // 選択ハンドルはクリップの外で描画（画像外にはみ出すこともあるため）
    for (int i = 0; i < layers.length; i++) {
      if (i != selectedLayerIndex) continue;
      final layer = layers[i];
      if (!layer.visible || layer.keyframes.isEmpty) continue;
      final state = layer.getStateAt(currentTime);
      final cx = dst.left + state.position.dx * scale;
      final cy = dst.top + state.position.dy * scale;
      final w = state.size.width * scale;
      final h = state.size.height * scale;
      final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
      _drawSelection(canvas, rect, state, cx, cy);
    }
  }

  double _fitScale(Size canvasSize) {
    final sx = canvasSize.width / mediaSize.width;
    final sy = canvasSize.height / mediaSize.height;
    return sx < sy ? sx : sy;
  }

  void _drawMosaicRegion(
    Canvas canvas,
    Rect imageDst,
    double scale,
    MosaicLayer layer,
    Keyframe state, {
    bool isSelected = false,
  }) {
    final cx = imageDst.left + state.position.dx * scale;
    final cy = imageDst.top + state.position.dy * scale;
    final w = state.size.width * scale;
    final h = state.size.height * scale;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    canvas.save();
    // 反転モード時は画像全体が対象のため回転は適用しない
    if (!layer.inverted) {
      canvas.translate(cx, cy);
      canvas.rotate(state.rotation);
      canvas.translate(-cx, -cy);
    }

    // 形状でクリップ
    final shapePath = ShapePaths.of(layer.shape, rect);

    if (layer.inverted) {
      // 反転: 画像領域から形状パスを除外
      final outer = Path()..addRect(imageDst);
      final inverted =
          Path.combine(PathOperation.difference, outer, shapePath);
      canvas.clipPath(inverted);
    } else {
      canvas.clipPath(shapePath);
    }

    // 反転時のエフェクト描画範囲は画像全体
    final effectRect = layer.inverted ? imageDst : rect;

    switch (layer.type) {
      case MosaicType.pixelate:
        _drawPixelate(canvas, effectRect, state.intensity, scale);
        break;
      case MosaicType.blur:
        _drawBlur(canvas, effectRect, state.intensity, imageDst);
        break;
      case MosaicType.fill:
        canvas.drawRect(effectRect, Paint()..color = Color(layer.fillColor));
        break;
      case MosaicType.noise:
        _drawNoise(canvas, effectRect, state.intensity, scale);
        break;
    }

    canvas.restore();
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

  void _drawNoise(
      Canvas canvas, Rect rect, double intensity, double scale) {
    final pixelSize = max(1.0, intensity * scale * 0.15);
    final paint = Paint();
    const seed = 42;
    for (double y = rect.top; y < rect.bottom; y += pixelSize) {
      for (double x = rect.left; x < rect.right; x += pixelSize) {
        final h = ((x.toInt() * 73856093) ^
                (y.toInt() * 19349663) ^
                seed) &
            0xFF;
        paint.color = Color.fromARGB(255, h, h, h);
        final bw = min(pixelSize, rect.right - x);
        final bh = min(pixelSize, rect.bottom - y);
        canvas.drawRect(Rect.fromLTWH(x, y, bw, bh), paint);
      }
    }
  }

  void _drawBlur(
      Canvas canvas, Rect rect, double intensity, Rect imageDst) {
    final sigma = max(1.0, intensity * 0.8);
    final paint = Paint()
      ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    canvas.saveLayer(rect, paint);
    if (mediaImage != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        mediaImage!.width.toDouble(),
        mediaImage!.height.toDouble(),
      );
      canvas.drawImageRect(mediaImage!, src, imageDst, Paint());
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

    const accentColor = Color(0xFF7C6FF0);

    // 破線ボーダー
    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final inflated = rect.inflate(2);
    _drawDashedRect(canvas, inflated, borderPaint,
        dashLength: 7, gapLength: 4);

    // コーナーハンドル
    const handleRadius = 8.0;
    final handleFill = Paint()..color = Colors.white;
    final handleStroke = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final handleShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final corners = [
      inflated.topLeft,
      inflated.topRight,
      inflated.bottomLeft,
      inflated.bottomRight,
    ];
    for (final corner in corners) {
      canvas.drawCircle(corner, handleRadius + 1, handleShadow);
      canvas.drawCircle(corner, handleRadius, handleFill);
      canvas.drawCircle(corner, handleRadius, handleStroke);
    }

    // エッジ中点の小ハンドル
    const edgeRadius = 4.5;
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

    canvas.restore();
  }

  void _drawDashedRect(
      Canvas canvas, Rect rect, Paint paint,
      {double dashLength = 6, double gapLength = 4}) {
    final totalDash = dashLength + gapLength;
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint, totalDash,
        dashLength);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint,
        totalDash, dashLength);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint,
        totalDash, dashLength);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint,
        totalDash, dashLength);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint,
      double totalDash, double dashLength) {
    final delta = end - start;
    final length = delta.distance;
    if (length == 0) return;
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
    // レイヤー内部プロパティ（type/shape/intensity等）の変更を確実に検出するため、
    // 常に再描画させる。画像編集用途では再描画コストより即時反映を優先。
    return true;
  }
}
