import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class TimelinePanel extends StatelessWidget {
  final List<MosaicLayer> layers;
  final int selectedLayerIndex;
  final Duration currentTime;
  final Duration totalDuration;
  final ValueChanged<Duration> onSeek;
  final void Function(int layerIndex) onAddKeyframe;
  final void Function(int layerIndex, int keyframeIndex) onSelectKeyframe;
  final void Function(int layerIndex, int keyframeIndex) onDeleteKeyframe;

  const TimelinePanel({
    super.key,
    required this.layers,
    required this.selectedLayerIndex,
    required this.currentTime,
    required this.totalDuration,
    required this.onSeek,
    required this.onAddKeyframe,
    required this.onSelectKeyframe,
    required this.onDeleteKeyframe,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = totalDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Time ruler + scrubber
        SizedBox(
          height: 32,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth - 80;
              return GestureDetector(
                onHorizontalDragUpdate: (d) {
                  final ratio =
                      ((d.localPosition.dx - 80) / trackWidth).clamp(0.0, 1.0);
                  onSeek(Duration(milliseconds: (ratio * totalMs).round()));
                },
                onTapDown: (d) {
                  final ratio =
                      ((d.localPosition.dx - 80) / trackWidth).clamp(0.0, 1.0);
                  onSeek(Duration(milliseconds: (ratio * totalMs).round()));
                },
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _TimeRulerPainter(
                    currentTime: currentTime,
                    totalDuration: totalDuration,
                    labelOffset: 80,
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1, color: AppTheme.borderColor),
        // Layer tracks (not in Expanded - uses intrinsic height)
        ...layers.asMap().entries.map((entry) {
          final index = entry.key;
          return _LayerTrack(
            layer: entry.value,
            layerIndex: index,
            isSelected: index == selectedLayerIndex,
            currentTime: currentTime,
            totalDuration: totalDuration,
            onAddKeyframe: () => onAddKeyframe(index),
            onSelectKeyframe: (ki) => onSelectKeyframe(index, ki),
            onDeleteKeyframe: (ki) => onDeleteKeyframe(index, ki),
          );
        }),
      ],
    );
  }
}

class _TimeRulerPainter extends CustomPainter {
  final Duration currentTime;
  final Duration totalDuration;
  final double labelOffset;

  _TimeRulerPainter({
    required this.currentTime,
    required this.totalDuration,
    required this.labelOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalMs = totalDuration.inMilliseconds.toDouble();
    if (totalMs <= 0) return;

    final trackWidth = size.width - labelOffset;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppTheme.bgTertiary,
    );

    // Time markers
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final interval = _getTickInterval(totalMs);
    for (double ms = 0; ms <= totalMs; ms += interval) {
      final x = labelOffset + (ms / totalMs) * trackWidth;
      canvas.drawLine(
        Offset(x, size.height - 8),
        Offset(x, size.height),
        Paint()..color = AppTheme.borderLight..strokeWidth = 1,
      );
      textPainter.text = TextSpan(
        text: _formatTime(Duration(milliseconds: ms.round())),
        style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, 2));
    }

    // Playhead
    final playX = labelOffset + (currentTime.inMilliseconds / totalMs) * trackWidth;
    final headPaint = Paint()..color = AppTheme.accent..strokeWidth = 2;
    canvas.drawLine(Offset(playX, 0), Offset(playX, size.height), headPaint);
    // Triangle at top
    final path = Path()
      ..moveTo(playX - 5, 0)
      ..lineTo(playX + 5, 0)
      ..lineTo(playX, 6)
      ..close();
    canvas.drawPath(path, Paint()..color = AppTheme.accent);
  }

  double _getTickInterval(double totalMs) {
    if (totalMs < 5000) return 500;
    if (totalMs < 15000) return 1000;
    if (totalMs < 60000) return 5000;
    return 10000;
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 100;
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '$s.${ms}s';
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter old) {
    return old.currentTime != currentTime || old.totalDuration != totalDuration;
  }
}

class _LayerTrack extends StatelessWidget {
  final MosaicLayer layer;
  final int layerIndex;
  final bool isSelected;
  final Duration currentTime;
  final Duration totalDuration;
  final VoidCallback onAddKeyframe;
  final ValueChanged<int> onSelectKeyframe;
  final ValueChanged<int> onDeleteKeyframe;

  const _LayerTrack({
    required this.layer,
    required this.layerIndex,
    required this.isSelected,
    required this.currentTime,
    required this.totalDuration,
    required this.onAddKeyframe,
    required this.onSelectKeyframe,
    required this.onDeleteKeyframe,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = totalDuration.inMilliseconds.toDouble();

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.accent.withAlpha(10) : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Layer label
          SizedBox(
            width: 80,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      layer.name,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onAddKeyframe,
                    child: const Icon(Icons.add, size: 14, color: AppTheme.accent),
                  ),
                ],
              ),
            ),
          ),
          // Keyframe track
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                return Stack(
                  children: [
                    // Track line
                    Positioned(
                      left: 0, right: 0, top: 17,
                      child: Container(height: 2, color: AppTheme.bgHover),
                    ),
                    // Active range
                    if (layer.keyframes.length >= 2)
                      Positioned(
                        left: (layer.keyframes.first.time.inMilliseconds / totalMs) * trackWidth,
                        right: trackWidth - (layer.keyframes.last.time.inMilliseconds / totalMs) * trackWidth,
                        top: 15,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withAlpha(40),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    // Keyframe diamonds
                    ...layer.keyframes.asMap().entries.map((entry) {
                      final ki = entry.key;
                      final kf = entry.value;
                      final x = (kf.time.inMilliseconds / totalMs) * trackWidth;
                      return Positioned(
                        left: x - 7,
                        top: 11,
                        child: GestureDetector(
                          onTap: () => onSelectKeyframe(ki),
                          onLongPress: () => onDeleteKeyframe(ki),
                          child: Transform.rotate(
                            angle: 0.785398, // 45 degrees
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppTheme.accent,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
