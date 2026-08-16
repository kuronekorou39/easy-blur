import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// 動画再生コントロール（2段構成）
///
/// 上段: 時刻 + プログレスバー + 総時間 + ズーム
///   - ズーム（×1/×2/×5/×10）中は再生位置周辺の時間窓のみを
///     スライダーが担当し、細かいシークができる。
///     下のミニバーが動画全体のどこを見ているかを示す
/// 下段: ◀ ⏵/⏸ ▶ + 速度
///   - 短タップ: 現在のスキップ間隔だけ移動
///   - 長押し: 0.5s / 1s / 5s / 10s / 30s からスキップ間隔を選択
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

  /// タイムラインのズーム倍率。1 で全体表示
  double _zoom = 1.0;

  /// ドラッグ中に固定するズーム窓（再生位置への追従で窓が動くのを防ぐ）
  double? _dragWinStartMs;
  double? _dragWinEndMs;

  /// 選択肢
  static const List<int> _skipOptions = [500, 1000, 5000, 10000, 30000];

  /// 再生速度の選択肢
  static const List<double> _speedOptions = [0.1, 0.2, 0.5, 1.0, 2.0];

  /// ズーム倍率の選択肢
  static const List<double> _zoomOptions = [1, 2, 5, 10];

  void _seekBy(int deltaMs) {
    final newMs = (widget.currentTime.inMilliseconds + deltaMs)
        .clamp(0, widget.totalDuration.inMilliseconds);
    widget.onSeek(Duration(milliseconds: newMs));
  }

  /// 指定ボタン位置から選択メニューを開く（スキップ・速度・ズーム共用）
  Future<void> _showOptionMenu<T extends Object>({
    required BuildContext buttonContext,
    required List<T> options,
    required T current,
    required String Function(T) format,
    required ValueChanged<T> onSelected,
  }) async {
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

    final selected = await showMenu<T>(
      context: buttonContext,
      position: position,
      color: AppTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: AppTheme.borderLight.withValues(alpha: 0.5),
        ),
      ),
      items: options.map((option) {
        final isCurrent = option == current;
        return PopupMenuItem<T>(
          value: option,
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
                format(option),
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
      onSelected(selected);
    }
  }

  Future<void> _showSkipMenu(BuildContext buttonContext) =>
      _showOptionMenu<int>(
        buttonContext: buttonContext,
        options: _skipOptions,
        current: _skipMs,
        format: _formatSkip,
        onSelected: (ms) => setState(() => _skipMs = ms),
      );

  Future<void> _showSpeedMenu(BuildContext buttonContext) =>
      _showOptionMenu<double>(
        buttonContext: buttonContext,
        options: _speedOptions,
        current: widget.playbackSpeed,
        format: _formatSpeed,
        onSelected: (speed) => widget.onSpeedChanged?.call(speed),
      );

  Future<void> _showZoomMenu(BuildContext buttonContext) =>
      _showOptionMenu<double>(
        buttonContext: buttonContext,
        options: _zoomOptions,
        current: _zoom,
        format: (z) => '×${z.toInt()}',
        onSelected: (z) => setState(() => _zoom = z),
      );

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

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.totalDuration.inMilliseconds.toDouble();
    final curMs = widget.currentTime.inMilliseconds.toDouble();

    // ズーム窓の計算。通常は再生位置を中央に追従、ドラッグ中は固定
    double winStartMs = 0.0;
    double winEndMs = totalMs;
    if (_zoom > 1.0 && totalMs > 0) {
      if (_dragWinStartMs != null && _dragWinEndMs != null) {
        winStartMs = _dragWinStartMs!;
        winEndMs = _dragWinEndMs!;
      } else {
        final winLen = totalMs / _zoom;
        winStartMs = (curMs - winLen / 2).clamp(0.0, totalMs - winLen);
        winEndMs = winStartMs + winLen;
      }
    }
    final winLenMs = winEndMs - winStartMs;
    final progress = winLenMs > 0
        ? ((curMs - winStartMs) / winLenMs).clamp(0.0, 1.0)
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
          // 上段: 時刻 + プログレスバー + 総時間 + ズーム
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
                    onChangeStart: (_) {
                      if (_zoom > 1.0) {
                        setState(() {
                          _dragWinStartMs = winStartMs;
                          _dragWinEndMs = winEndMs;
                        });
                      }
                    },
                    onChanged: (v) {
                      widget.onSeek(Duration(
                          milliseconds:
                              (winStartMs + v * winLenMs).round()));
                    },
                    onChangeEnd: (_) {
                      if (_dragWinStartMs != null) {
                        setState(() {
                          _dragWinStartMs = null;
                          _dragWinEndMs = null;
                        });
                      }
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
              const SizedBox(width: 8),
              _MenuChip(
                icon: Icons.zoom_in_rounded,
                label: '×${_zoom.toInt()}',
                isActive: _zoom > 1.0,
                compact: true,
                onTapMenu: _showZoomMenu,
              ),
            ],
          ),
          // ズーム中: 全体のどこを表示しているかを示すミニバー（タップでシーク）
          if (_zoom > 1.0 && totalMs > 0) ...[
            const SizedBox(height: 2),
            SizedBox(
              height: 12,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final winLeft = (winStartMs / totalMs * w);
                  final winWidth =
                      math.max(8.0, winLenMs / totalMs * w);
                  final curLeft = (curMs / totalMs * w) - 1.5;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final pct =
                          (d.localPosition.dx / w).clamp(0.0, 1.0);
                      widget.onSeek(Duration(
                          milliseconds: (pct * totalMs).round()));
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 全体トラック
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 4,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppTheme.bgHover,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                        // 表示中の窓
                        Positioned(
                          left: winLeft,
                          top: 3,
                          child: Container(
                            width: winWidth,
                            height: 5,
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.accent.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                        // 再生位置
                        Positioned(
                          left: curLeft,
                          top: 1,
                          child: Container(
                            width: 3,
                            height: 9,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
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
                        child: _MenuChip(
                          icon: Icons.speed_rounded,
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

/// メニュー付きチップボタン（速度・ズーム共用）。isActive でアクセント表示
class _MenuChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool compact;
  final void Function(BuildContext) onTapMenu;

  const _MenuChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTapMenu,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 26.0 : 44.0;
    final iconSize = compact ? 13.0 : 16.0;
    final fontSize = compact ? 10.0 : 11.0;
    final hPad = compact ? 7.0 : 9.0;
    return Builder(
      builder: (ctx) => GestureDetector(
        onTap: () => onTapMenu(ctx),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPad),
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
                icon,
                size: iconSize,
                color: isActive
                    ? AppTheme.accentBright
                    : AppTheme.textPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
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
