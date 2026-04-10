import 'package:flutter/material.dart';
import '../utils/theme.dart';

class CompactPlaybackBar extends StatelessWidget {
  final bool isPlaying;
  final Duration currentTime;
  final Duration totalDuration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;

  const CompactPlaybackBar({
    super.key,
    required this.isPlaying,
    required this.currentTime,
    required this.totalDuration,
    required this.onTogglePlay,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = totalDuration.inMilliseconds.toDouble();
    final progress = totalMs > 0
        ? (currentTime.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: onTogglePlay,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accent.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedSwitcher(
                duration: AppTheme.animFast,
                child: Icon(
                  isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(isPlaying),
                  size: 22,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Time text
          Text(
            _formatDuration(currentTime),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          // Seek bar
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppTheme.accent,
                inactiveTrackColor: AppTheme.bgHover,
                thumbColor: AppTheme.accent,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
                overlayColor: AppTheme.accent.withAlpha(30),
              ),
              child: Slider(
                value: progress,
                onChanged: (v) {
                  onSeek(Duration(
                      milliseconds: (v * totalMs).round()));
                },
              ),
            ),
          ),
          // Total time
          Text(
            _formatDuration(totalDuration),
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
