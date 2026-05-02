import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import '../models/models.dart';

/// 各形状の Path を生成する共通ユーティリティ
///
/// プレビュー（ClipPath）、画像保存（Canvas.clipPath）の両方で使用される。
/// OpenGL シェーダー側は別途同等の判定式が GLSL で実装されている。
class ShapePaths {
  /// 指定矩形に内接する形状の Path を返す。
  /// [rotationRadians] が 0 でなければ矩形中心を基準に回転を適用。
  static Path of(MosaicShape shape, Rect rect,
      {double rotationRadians = 0}) {
    final base = _base(shape, rect);
    if (rotationRadians == 0) return base;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final cosR = cos(rotationRadians);
    final sinR = sin(rotationRadians);
    // 中心基準の回転行列を Float64List で構築
    final matrix = Float64List(16);
    matrix[0] = cosR;
    matrix[1] = sinR;
    matrix[4] = -sinR;
    matrix[5] = cosR;
    matrix[10] = 1;
    matrix[15] = 1;
    matrix[12] = cx - cx * cosR + cy * sinR;
    matrix[13] = cy - cx * sinR - cy * cosR;
    return base.transform(matrix);
  }

  static Path _base(MosaicShape shape, Rect rect) {
    switch (shape) {
      case MosaicShape.rectangle:
        return Path()
          ..addRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(4)));
      case MosaicShape.ellipse:
        return Path()..addOval(rect);
      case MosaicShape.triangle:
        return _triangle(rect);
      case MosaicShape.heart:
        return _heart(rect);
    }
  }

  /// 上向き三角形（頂点が上、底辺が下）
  static Path _triangle(Rect r) {
    return Path()
      ..moveTo(r.left + r.width / 2, r.top)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
  }

  /// ベジエ曲線で標準的なハート形を構築
  /// 矩形の幅/高さに合わせて自動スケール
  static Path _heart(Rect r) {
    final w = r.width;
    final h = r.height;
    final cx = r.left + w / 2;
    final topNotch = r.top + h * 0.25;

    return Path()
      ..moveTo(cx, topNotch)
      // 左半分（上の山→左の腹→下の頂点）
      ..cubicTo(
        r.left + w * 0.15, r.top - h * 0.05,
        r.left - w * 0.05, r.top + h * 0.40,
        cx, r.bottom,
      )
      // 右半分（下の頂点→右の腹→上の山→開始点）
      ..cubicTo(
        r.right + w * 0.05, r.top + h * 0.40,
        r.right - w * 0.15, r.top - h * 0.05,
        cx, topNotch,
      )
      ..close();
  }
}
