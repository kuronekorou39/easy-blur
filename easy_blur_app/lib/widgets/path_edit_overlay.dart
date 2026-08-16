import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

/// 選択中レイヤーの移動経路を表示・編集するオーバーレイ。
/// - 経路全体を線で表示（現在時刻より過去は薄く、未来は濃く）
/// - 経路点はドラッグで位置を修正、タップでその時刻へシーク
class PathEditOverlay extends StatelessWidget {
  final List<PathPoint> pathKeyframes;
  final Rect videoRect;
  final double scale;
  final Duration currentTime;
  final bool enabled;
  final void Function(int index, Offset canvasDelta) onMovePoint;
  final void Function(int index) onTapPoint;

  const PathEditOverlay({
    super.key,
    required this.pathKeyframes,
    required this.videoRect,
    required this.scale,
    required this.currentTime,
    required this.enabled,
    required this.onMovePoint,
    required this.onTapPoint,
  });

  /// 経路点のタップ・ドラッグ判定サイズ
  static const double _hitSize = 30;

  Offset _toCanvas(Offset videoPos) => Offset(
        videoRect.left + videoPos.dx * scale,
        videoRect.top + videoPos.dy * scale,
      );

  @override
  Widget build(BuildContext context) {
    // 現在時刻に最も近い経路点を強調表示
    int nearestIndex = 0;
    int nearestDiff = 1 << 62;
    for (int i = 0; i < pathKeyframes.length; i++) {
      final diff = (pathKeyframes[i].time.inMilliseconds -
              currentTime.inMilliseconds)
          .abs();
      if (diff < nearestDiff) {
        nearestDiff = diff;
        nearestIndex = i;
      }
    }

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: Size.infinite,
              painter: _PathPainter(
                points:
                    pathKeyframes.map((p) => _toCanvas(p.position)).toList(),
                times: pathKeyframes.map((p) => p.time).toList(),
                currentTime: currentTime,
              ),
            ),
          ),
          for (int i = 0; i < pathKeyframes.length; i++)
            _buildDot(i, isNearest: i == nearestIndex),
        ],
      ),
    );
  }

  Widget _buildDot(int index, {required bool isNearest}) {
    final center = _toCanvas(pathKeyframes[index].position);
    final dotSize = isNearest ? 13.0 : 9.0;
    return Positioned(
      left: center.dx - _hitSize / 2,
      top: center.dy - _hitSize / 2,
      width: _hitSize,
      height: _hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTapPoint(index),
        onPanUpdate:
            enabled ? (d) => onMovePoint(index, d.delta) : null,
        child: Center(
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: isNearest ? AppTheme.accentBright : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isNearest ? Colors.white : AppTheme.accent,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 経路の折れ線。現在時刻より過去の区間は薄く描画する
class _PathPainter extends CustomPainter {
  final List<Offset> points;
  final List<Duration> times;
  final Duration currentTime;

  _PathPainter({
    required this.points,
    required this.times,
    required this.currentTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final pastPaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final futurePaint = Paint()
      ..color = AppTheme.accentBright.withValues(alpha: 0.75)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length - 1; i++) {
      final aMs = times[i].inMilliseconds;
      final bMs = times[i + 1].inMilliseconds;
      final curMs = currentTime.inMilliseconds;
      if (bMs <= curMs) {
        // 全区間が過去
        canvas.drawLine(points[i], points[i + 1], pastPaint);
      } else if (aMs >= curMs) {
        // 全区間が未来
        canvas.drawLine(points[i], points[i + 1], futurePaint);
      } else {
        // 現在時刻をまたぐ区間は分割して描画
        final t = bMs == aMs ? 0.0 : (curMs - aMs) / (bMs - aMs);
        final mid = Offset.lerp(points[i], points[i + 1], t)!;
        canvas.drawLine(points[i], mid, pastPaint);
        canvas.drawLine(mid, points[i + 1], futurePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PathPainter old) =>
      old.points != points ||
      old.times != times ||
      old.currentTime != currentTime;
}
