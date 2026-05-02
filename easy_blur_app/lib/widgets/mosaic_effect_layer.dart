import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/shape_paths.dart';

/// プレビュー用のモザイク効果を Widget で表現する。
/// BackdropFilter を使うことで、下層にある VideoPlayer や Image の実フレームに
/// フィルタを適用する。出力(ネイティブ)との見た目を極力一致させる。
///
/// - Blur: ImageFilter.blur で実フレームをブラー（出力とほぼ同一）
/// - Pixelate: 強めの ImageFilter.blur + グリッドラインで量子化風に近似
/// - Blackout: 単色塗り
///
/// 形状（矩形/楕円）は ClipPath でマスク。
class MosaicEffectLayer extends StatelessWidget {
  final Rect canvasRect;
  final MosaicType type;
  final MosaicShape shape;
  final double intensity;

  /// true: 矩形の外側にエフェクトを適用
  final bool inverted;

  /// fill エフェクトで使用する色（ARGB値）
  final int fillColor;

  /// レイヤーの回転（ラジアン、矩形中心基準）
  final double rotation;

  const MosaicEffectLayer({
    super.key,
    required this.canvasRect,
    required this.type,
    required this.shape,
    required this.intensity,
    this.inverted = false,
    this.fillColor = 0xFF000000,
    this.rotation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final effect = _buildEffect();

    if (inverted) {
      // 反転モード：親全体を覆い、回転後の形状領域を「穴」として抜く
      return Positioned.fill(
        child: IgnorePointer(
          child: ClipPath(
            clipper: _InvertedShapeClipper(
              hole: canvasRect,
              shape: shape,
              rotation: rotation,
            ),
            child: effect,
          ),
        ),
      );
    }

    // 通常モード：形状でクリップ → Transform で矩形中心を基準に回転
    return Positioned.fromRect(
      rect: canvasRect,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: rotation,
          alignment: Alignment.center,
          child: ClipPath(
            clipper: _ShapeClipper(shape: shape),
            child: effect,
          ),
        ),
      ),
    );
  }

  Widget _buildEffect() {
    switch (type) {
      case MosaicType.blur:
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: intensity * 0.8,
            sigmaY: intensity * 0.8,
            tileMode: TileMode.clamp,
          ),
          child: const SizedBox.expand(),
        );

      case MosaicType.pixelate:
        // ピクセレートは Flutter 標準では量子化シェーダーがないため、
        // 強いブラー + 格子線パターンの2段で疑似再現。
        // 出力(OpenGL)のニアレストサンプリング結果とは完全同一ではないが、
        // ブロック感と同等の視認性を確保。
        final blockSize = intensity.clamp(4.0, 50.0);
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: intensity * 1.2,
                  sigmaY: intensity * 1.2,
                  tileMode: TileMode.clamp,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _PixelateGridPainter(blockSize: blockSize),
              ),
            ),
          ],
        );

      case MosaicType.fill:
        return Container(color: Color(fillColor));

      case MosaicType.noise:
        // ノイズ：微細なランダムドット模様をCustomPainterで描画
        return CustomPaint(
          painter: _NoisePainter(intensity: intensity),
          child: const SizedBox.expand(),
        );
    }
  }
}

class _NoisePainter extends CustomPainter {
  final double intensity;
  _NoisePainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    // 決定論的ノイズ（毎フレーム変わらない）
    final pixelSize = (intensity * 0.15).clamp(1.0, 4.0);
    final paint = Paint();
    final seed = 42;
    for (double y = 0; y < size.height; y += pixelSize) {
      for (double x = 0; x < size.width; x += pixelSize) {
        // シンプルな疑似乱数で決定論的に色決定
        final h = ((x.toInt() * 73856093) ^
                (y.toInt() * 19349663) ^
                seed) &
            0xFF;
        paint.color = Color.fromARGB(255, h, h, h);
        canvas.drawRect(Rect.fromLTWH(x, y, pixelSize, pixelSize), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}

/// レイヤー矩形をローカル座標で形状クリップ
class _ShapeClipper extends CustomClipper<Path> {
  final MosaicShape shape;

  _ShapeClipper({required this.shape});

  @override
  Path getClip(Size size) {
    return ShapePaths.of(shape, Rect.fromLTWH(0, 0, size.width, size.height));
  }

  @override
  bool shouldReclip(_ShapeClipper old) => old.shape != shape;
}

/// 反転モザイク用のクリッパー。親全体から指定形状（回転含む）の穴をくり抜く。
class _InvertedShapeClipper extends CustomClipper<Path> {
  final Rect hole;
  final MosaicShape shape;
  final double rotation;

  _InvertedShapeClipper({
    required this.hole,
    required this.shape,
    required this.rotation,
  });

  @override
  Path getClip(Size size) {
    final outer = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = ShapePaths.of(shape, hole, rotationRadians: rotation);
    return Path.combine(PathOperation.difference, outer, inner);
  }

  @override
  bool shouldReclip(_InvertedShapeClipper old) =>
      old.hole != hole ||
      old.shape != shape ||
      old.rotation != rotation;
}

class _PixelateGridPainter extends CustomPainter {
  final double blockSize;

  _PixelateGridPainter({required this.blockSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (blockSize < 2) return;
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    // 縦線
    for (double x = 0; x < size.width; x += blockSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // 横線
    for (double y = 0; y < size.height; y += blockSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelateGridPainter oldDelegate) =>
      oldDelegate.blockSize != blockSize;
}
