import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// 動画再生コントロール（2段構成）
/// 上段: 時刻 + プログレスバー + 総時間
/// 下段: ◀◀(1秒) ◀(1フレーム) ▶/⏸ ▶(1フレーム) ▶▶(1秒)
class CompactPlaybackBar extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final Duration currentTime;
  final Duration totalDuration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;

  /// フレームレート (FPS)。デフォルト 30
  final int frameRate;

  const CompactPlaybackBar({
    super.key,
    required this.isPlaying,
    required this.currentTime,
    required this.totalDuration,
    required this.onTogglePlay,
    required this.onSeek,
    this.isLoading = false,
    this.frameRate = 30,
  });

  int get _frameMs => (1000.0 / frameRate).round();

  void _seekBy(int deltaMs) {
    final newMs =
        (currentTime.inMilliseconds + deltaMs).clamp(
            0, totalDuration.inMilliseconds);
    onSeek(Duration(milliseconds: newMs));
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = totalDuration.inMilliseconds.toDouble();
    final progress = totalMs > 0
        ? (currentTime.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(
              color: AppTheme.borderColor.withValues(alpha: 0.4), width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上段: 時刻 + プログレスバー + 総時間
          Row(
            children: [
              Text(
                _formatTime(currentTime, showFrames: true),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppTheme.accent,
                    inactiveTrackColor: AppTheme.bgHover,
                    thumbColor: AppTheme.accent,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6),
                    trackHeight: 3,
                    overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14),
                    overlayColor: AppTheme.accent.withValues(alpha: 0.15),
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
              const SizedBox(width: 8),
              Text(
                _formatTime(totalDuration),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // 下段: 3段階 × 左右のシーク + 再生ボタン
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SeekButton(
                icon: Icons.replay_10_rounded,
                label: '10s',
                onTap: () => _seekBy(-10000),
                holdDeltaMs: -10000,
                onHoldTick: _seekBy,
              ),
              _SeekButton(
                icon: Icons.fast_rewind_rounded,
                label: '1s',
                onTap: () => _seekBy(-1000),
                holdDeltaMs: -1000,
                onHoldTick: _seekBy,
              ),
              _SeekButton(
                icon: Icons.skip_previous_rounded,
                label: '1F',
                onTap: () => _seekBy(-_frameMs),
                holdDeltaMs: -_frameMs,
                onHoldTick: _seekBy,
              ),
              _PlayPauseButton(
                isPlaying: isPlaying,
                isLoading: isLoading,
                onTap: onTogglePlay,
              ),
              _SeekButton(
                icon: Icons.skip_next_rounded,
                label: '1F',
                onTap: () => _seekBy(_frameMs),
                holdDeltaMs: _frameMs,
                onHoldTick: _seekBy,
              ),
              _SeekButton(
                icon: Icons.fast_forward_rounded,
                label: '1s',
                onTap: () => _seekBy(1000),
                holdDeltaMs: 1000,
                onHoldTick: _seekBy,
              ),
              _SeekButton(
                icon: Icons.forward_10_rounded,
                label: '10s',
                onTap: () => _seekBy(10000),
                holdDeltaMs: 10000,
                onHoldTick: _seekBy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 時刻フォーマット。showFrames=true で m:ss.FF（FFは0.01秒精度）
  String _formatTime(Duration d, {bool showFrames = false}) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (!showFrames) {
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    // 1/100秒精度の端数
    final ff = ((d.inMilliseconds % 1000) / 10).floor();
    return '$m:${s.toString().padLeft(2, '0')}.${ff.toString().padLeft(2, '0')}';
  }
}

/// シークボタン（タップ / 長押し対応、アイコン+刻み量ラベル）
class _SeekButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int holdDeltaMs;
  final ValueChanged<int> onHoldTick;

  const _SeekButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.holdDeltaMs,
    required this.onHoldTick,
  });

  @override
  State<_SeekButton> createState() => _SeekButtonState();
}

class _SeekButtonState extends State<_SeekButton> {
  bool _holding = false;

  Future<void> _startHold() async {
    _holding = true;
    await Future.delayed(const Duration(milliseconds: 250));
    while (_holding && mounted) {
      widget.onHoldTick(widget.holdDeltaMs);
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  void _stopHold() {
    _holding = false;
  }

  @override
  void dispose() {
    _holding = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _stopHold(),
      onLongPressCancel: _stopHold,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.bgHover.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: AppTheme.borderColor.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, size: 15, color: AppTheme.textPrimary),
            const SizedBox(height: 1),
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    if (isLoading) {
      icon = const SizedBox(
        key: ValueKey('loading'),
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: Colors.white,
        ),
      );
    } else {
      icon = Icon(
        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(isPlaying ? 'pause' : 'play'),
        size: 24,
        color: Colors.white,
      );
    }

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        width: 44,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: AppTheme.animFast,
            child: icon,
          ),
        ),
      ),
    );
  }
}
