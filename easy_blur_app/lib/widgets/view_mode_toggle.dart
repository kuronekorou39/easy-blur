import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

enum VideoViewMode { shrink, fixed }

enum VerticalAnchor { top, center, bottom }

/// 動画エディタの上部に表示される表示モード切替ボタン。
/// - 縮小モード / 固定モードの切替
/// - 固定モード時のみ 上 / 中 / 下 の縦シフト切替
class ViewModeToggle extends StatelessWidget {
  final VideoViewMode mode;
  final VerticalAnchor anchor;
  final ValueChanged<VideoViewMode> onModeChanged;
  final ValueChanged<VerticalAnchor> onAnchorChanged;

  const ViewModeToggle({
    super.key,
    required this.mode,
    required this.anchor,
    required this.onModeChanged,
    required this.onAnchorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // モード切替セグメント
        _Segment(
          options: const [
            _SegmentOption(
              icon: Icons.compress_rounded,
              tooltip: '縮小モード',
              value: VideoViewMode.shrink,
            ),
            _SegmentOption(
              icon: Icons.push_pin_rounded,
              tooltip: '固定モード',
              value: VideoViewMode.fixed,
            ),
          ],
          selected: mode,
          onSelected: (v) => onModeChanged(v as VideoViewMode),
        ),
        // 固定モード時のみ縦シフト
        AnimatedSize(
          duration: AppTheme.animFast,
          curve: Curves.easeOutCubic,
          child: mode == VideoViewMode.fixed
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 8),
                    _Segment(
                      options: const [
                        _SegmentOption(
                          icon: Icons.vertical_align_top_rounded,
                          tooltip: '上を見る',
                          value: VerticalAnchor.top,
                        ),
                        _SegmentOption(
                          icon: Icons.vertical_align_center_rounded,
                          tooltip: '中央',
                          value: VerticalAnchor.center,
                        ),
                        _SegmentOption(
                          icon: Icons.vertical_align_bottom_rounded,
                          tooltip: '下を見る',
                          value: VerticalAnchor.bottom,
                        ),
                      ],
                      selected: anchor,
                      onSelected: (v) => onAnchorChanged(v as VerticalAnchor),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SegmentOption {
  final IconData icon;
  final String tooltip;
  final Object value;

  const _SegmentOption({
    required this.icon,
    required this.tooltip,
    required this.value,
  });
}

class _Segment extends StatelessWidget {
  final List<_SegmentOption> options;
  final Object selected;
  final ValueChanged<Object> onSelected;

  const _Segment({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius:
                BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: options.map((o) {
              final isSelected = o.value == selected;
              return Tooltip(
                message: o.tooltip,
                child: GestureDetector(
                  onTap: () => onSelected(o.value),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: AppTheme.animFast,
                    width: 34,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall),
                    ),
                    child: Icon(
                      o.icon,
                      size: 16,
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
