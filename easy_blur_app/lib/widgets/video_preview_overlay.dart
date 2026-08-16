import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'compact_playback_bar.dart';
import 'mosaic_effect_layer.dart';

/// 出力相当のリアルタイム動画プレビュー。
/// 編集ハンドルなしでモザイクを適用した状態のまま再生・シークできる。
class VideoPreviewOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  final List<MosaicLayer> layers;
  final Size videoSize;
  final Duration currentTime;
  final Duration totalDuration;
  final bool isPlaying;
  final bool isLoading;
  final double playbackSpeed;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;
  final VoidCallback onClose;

  const VideoPreviewOverlay({
    super.key,
    required this.controller,
    required this.layers,
    required this.videoSize,
    required this.currentTime,
    required this.totalDuration,
    required this.isPlaying,
    required this.isLoading,
    required this.playbackSpeed,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onSpeedChanged,
    this.onScrubStart,
    this.onScrubEnd,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.96),
        child: Column(
          children: [
            SizedBox(height: padding.top),
            _buildHeader(),
            Expanded(child: _buildVideoArea()),
            CompactPlaybackBar(
              isPlaying: isPlaying,
              isLoading: isLoading,
              currentTime: currentTime,
              totalDuration: totalDuration,
              onTogglePlay: onTogglePlay,
              onSeek: onSeek,
              playbackSpeed: playbackSpeed,
              onSpeedChanged: onSpeedChanged,
              onScrubStart: onScrubStart,
              onScrubEnd: onScrubEnd,
            ),
            SizedBox(height: padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                  color: AppTheme.borderLight.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_rounded,
                  size: 14,
                  color: AppTheme.accentBright,
                ),
                const SizedBox(width: 6),
                Text(
                  '出力プレビュー',
                  style: AppTheme.textBodyStrong.copyWith(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        if (videoSize.isEmpty || canvasSize.isEmpty) {
          return const SizedBox.expand();
        }
        final sx = canvasSize.width / videoSize.width;
        final sy = canvasSize.height / videoSize.height;
        final scale = sx < sy ? sx : sy;
        final videoRect = Rect.fromLTWH(
          (canvasSize.width - videoSize.width * scale) / 2,
          (canvasSize.height - videoSize.height * scale) / 2,
          videoSize.width * scale,
          videoSize.height * scale,
        );

        return GestureDetector(
          onTap: onTogglePlay,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fromRect(
                rect: videoRect,
                child: VideoPlayer(controller),
              ),
              for (final layer in layers)
                if (layer.visible &&
                    layer.hasContent &&
                    layer.isActiveAt(currentTime))
                  _buildEffectLayer(layer, videoRect, scale),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEffectLayer(
      MosaicLayer layer, Rect videoRect, double scale) {
    final state = layer.getStateAt(currentTime);
    final rect = Rect.fromCenter(
      center: Offset(
        videoRect.left + state.position.dx * scale,
        videoRect.top + state.position.dy * scale,
      ),
      width: state.size.width * scale,
      height: state.size.height * scale,
    );
    return MosaicEffectLayer(
      key: ValueKey('preview_effect_${layer.id}'),
      canvasRect: rect,
      type: layer.type,
      shape: layer.shape,
      inverted: layer.inverted,
      fillColor: layer.fillColor,
      barAngle: layer.barAngle,
      intensity: state.intensity,
      rotation: state.rotation,
    );
  }
}
