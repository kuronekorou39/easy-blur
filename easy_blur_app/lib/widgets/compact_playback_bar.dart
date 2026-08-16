import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// 動画再生コントロール（2段構成）
///
/// 上段: 時刻 + プログレスバー + 総時間
/// 下段: ◀ ⏵/⏸ ▶ + 速度
///   - 短タップ: 現在のスキップ間隔だけ移動
///   - 長押し: 0.5s / 1s / 5s / 10s / 30s からスキップ間隔を選択
///   - ボタンには現在の間隔（"1s" 等）を表示
///   - 速度ボタン: タップで 0.1x〜2x を選択（onSpeedChanged 未指定なら非表示）
class CompactPlaybackBar extends StatefulWidget {
  final bool isPlaying;
  final bool isLoading;
  final Duration currentTime;
  final Duration totalDuration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final double playbackSpeed;
  final ValueChanged<double>? onSpeedChanged;

  const CompactPlaybackBar({
    super.key,
    required this.isPlaying,
    required this.currentTime,
    required this.totalDuration,
    required this.onTogglePlay,
    required this.onSeek,
    this.isLoading = false,
    this.playbackSpeed = 1.0,
    this.onSpeedChanged,
  });

  @override
  State<CompactPlaybackBar> createState() => _CompactPlaybackBarState();
}

class _CompactPlaybackBarState extends State<CompactPlaybackBar> {
  /// スキップ間隔（ミリ秒）。左右のボタンで共有
  int _skipMs = 1000;

  /// 選択肢
  static const List<int> _skipOptions = [500, 1000, 5000, 10000, 30000];

  /// 再生速度の選択肢
  static const List<double> _speedOptions = [0.1, 0.2, 0.5, 1.0, 2.0];

  void _seekBy(int deltaMs) {
    final newMs = (widget.currentTime.inMilliseconds + deltaMs)
        .clamp(0, widget.totalDuration.inMilliseconds);
    widget.onSeek(Duration(milliseconds: newMs));
  }

  /// 指定ボタン位置から長押しメニューを開く
  Future<void> _showSkipMenu(BuildContext buttonContext) async {
    final renderObject = buttonContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderObject.localToGlobal(Offset.zero, ancestor: overlay),
        renderObject.localToGlobal(
            renderObject.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<int>(
      context: buttonContext,
      position: position,
      color: AppTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: AppTheme.borderLight.withValues(alpha: 0.5),
        ),
      ),
      items: _skipOptions.map((ms) {
        final isCurrent = ms == _skipMs;
        return PopupMenuItem<int>(
          value: ms,
          child: Row(
            children: [
              Icon(
                isCurrent
                    ? Icons.check_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: isCurrent
                    ? AppTheme.accentBright
                    : AppTheme.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Text(
                _formatSkip(ms),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent
                      ? AppTheme.accentBright
                      : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      setState(() => _skipMs = selected);
    }
  }

  static String _formatSkip(int ms) {
    if (ms < 1000) {
      final s = ms / 1000;
      return '${s.toStringAsFixed(1)}s';
    }
    return '${ms ~/ 1000}s';
  }

  static String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toInt()}x';
    }
    return '${speed}x';
  }

  /// 速度ボタンからメニューを開く
  Future<void> _showSpeedMenu(BuildContext buttonContext) async {
    final renderObject = buttonContext.findRenderObject();
    if (renderObject is! RenderBox) return;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        renderObject.localToGlobal(Offset.zero, ancestor: overlay),
        renderObject.localToGlobal(
            renderObject.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<double>(
      context: buttonContext,
      position: position,
      color: AppTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: AppTheme.borderLight.withValues(alpha: 0.5),
        ),
      ),
      items: _speedOptions.map((speed) {
        final isCurrent = speed == widget.playbackSpeed;
        return PopupMenuItem<double>(
          value: speed,
          child: Row(
            children: [
              Icon(
                isCurrent
                    ? Icons.check_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: isCurrent
                    ? AppTheme.accentBright
                    : AppTheme.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Text(
                _formatSpeed(speed),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: isCurrent
                      ? AppTheme.accentBright
                      : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );

    if (selected != null && mounted) {
      widget.onSpeedChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.totalDuration.inMilliseconds.toDouble();
    final progress = totalMs > 0
        ? (widget.currentTime.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final label = _formatSkip(_skipMs);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(
              color: AppTheme.borderColor.withValues(alpha: 0.4),
              width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上段: 時刻 + プログレスバー + 総時間
          Row(
            children: [
              Text(
                _formatTime(widget.currentTime, showFraction: true),
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
                      widget.onSeek(Duration(
                          milliseconds: (v * totalMs).round()));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(widget.totalDuration),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 下段: 戻る / 再生 / 進む（右端に速度）
          Row(
            children: [
              const Spacer(),
              _SeekButton(
                icon: Icons.fast_rewind_rounded,
                label: label,
                onTap: () => _seekBy(-_skipMs),
                onLongPress: _showSkipMenu,
              ),
              const SizedBox(width: 16),
              _PlayPauseButton(
                isPlaying: widget.isPlaying,
                isLoading: widget.isLoading,
                onTap: widget.onTogglePlay,
              ),
              const SizedBox(width: 16),
              _SeekButton(
                icon: Icons.fast_forward_rounded,
                label: label,
                onTap: () => _seekBy(_skipMs),
                onLongPress: _showSkipMenu,
              ),
              Expanded(
                child: widget.onSpeedChanged == null
                    ? const SizedBox()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: _SpeedButton(
                          label: _formatSpeed(widget.playbackSpeed),
                          isActive: widget.playbackSpeed != 1.0,
                          onTapMenu: _showSpeedMenu,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 時刻表示。 showFraction=true で 0.1秒精度
  String _formatTime(Duration d, {bool showFraction = false}) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (!showFraction) {
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    final f = ((d.inMilliseconds % 1000) / 100).floor();
    return '$m:${s.toString().padLeft(2, '0')}.$f';
  }
}

/// 再生速度ボタン（タップでメニュー）。1x 以外のときはアクセント表示
class _SpeedButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final void Function(BuildContext) onTapMenu;

  const _SpeedButton({
    required this.label,
    required this.isActive,
    required this.onTapMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => GestureDetector(
        onTap: () => onTapMenu(ctx),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.accent.withValues(alpha: 0.22)
                : AppTheme.bgHover.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: isActive
                  ? AppTheme.accent.withValues(alpha: 0.6)
                  : AppTheme.borderColor.withValues(alpha: 0.4),
              width: isActive ? 1.0 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_rounded,
                size: 16,
                color: isActive
                    ? AppTheme.accentBright
                    : AppTheme.textPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? AppTheme.accentBright
                      : AppTheme.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// シークボタン（短タップで1回送り、長押しでメニュー）
class _SeekButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final void Function(BuildContext) onLongPress;

  const _SeekButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => GestureDetector(
        onTap: onTap,
        onLongPress: () => onLongPress(ctx),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 64,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.bgHover.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: AppTheme.borderColor.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
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
        width: 52,
        height: 44,
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
