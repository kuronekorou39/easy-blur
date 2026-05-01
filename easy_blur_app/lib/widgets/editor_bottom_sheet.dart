import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'layer_panel.dart';

/// シングルパネル型ボトムシート
/// 各レイヤーが展開式プロパティを持つため、タブ構造は不要。
/// - 折りたたみ時: ヘッダー（レイヤー数、追加ボタン）のみ
/// - 展開時: レイヤーリスト表示
class EditorBottomSheet extends StatefulWidget {
  final MosaicLayer? selectedLayer;
  final List<MosaicLayer> layers;
  final int selectedIndex;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<bool> onInvertedChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<int> onSelectLayer;
  final VoidCallback onAddLayer;
  final ValueChanged<int> onDeleteLayer;
  final ValueChanged<int> onToggleVisibility;
  final void Function(int oldIndex, int newIndex) onReorderLayers;

  // 動画専用: 時間範囲編集
  final bool showTimeRange;
  final Duration? currentTime;
  final Duration? totalDuration;
  final ValueChanged<int>? onSetStart;
  final ValueChanged<int>? onSetEnd;
  final ValueChanged<Duration>? onSeekTo;
  final ValueChanged<int>? onAddKeyframeAtCurrent;
  final ValueChanged<int>? onDeleteKeyframeAtCurrent;
  final void Function(int layerIndex, int keyframeIndex)? onDeleteKeyframe;

  const EditorBottomSheet({
    super.key,
    required this.selectedLayer,
    required this.layers,
    required this.selectedIndex,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onInvertedChanged,
    required this.onIntensityChanged,
    required this.onSelectLayer,
    required this.onAddLayer,
    required this.onDeleteLayer,
    required this.onToggleVisibility,
    required this.onReorderLayers,
    this.showTimeRange = false,
    this.currentTime,
    this.totalDuration,
    this.onSetStart,
    this.onSetEnd,
    this.onSeekTo,
    this.onAddKeyframeAtCurrent,
    this.onDeleteKeyframeAtCurrent,
    this.onDeleteKeyframe,
  });

  @override
  State<EditorBottomSheet> createState() => _EditorBottomSheetState();
}

class _EditorBottomSheetState extends State<EditorBottomSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: AppTheme.animNormal,
      value: 0,
    );
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _expandCtrl.forward();
      } else {
        _expandCtrl.reverse();
      }
    });
  }

  void _expand() {
    if (!_expanded) {
      setState(() {
        _expanded = true;
        _expandCtrl.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;

    final collapsedHeight = 56.0 + bottomInset;
    final expandedHeight = (screenH * 0.58).clamp(380.0, 620.0);

    return AnimatedBuilder(
      animation: _expandCtrl,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_expandCtrl.value);
        final height =
            collapsedHeight + (expandedHeight - collapsedHeight) * t;
        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.sheetRadius),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.sheetBackground.withValues(alpha: 0.94),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTheme.sheetRadius),
                  ),
                  border: Border(
                    top: BorderSide(
                        color: AppTheme.borderLight.withValues(alpha: 0.6),
                        width: 0.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 28,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildHandle(),
                    _buildHeader(),
                    if (_expanded)
                      Expanded(
                        child: LayerPanel(
                          layers: widget.layers,
                          selectedIndex: widget.selectedIndex,
                          onSelect: widget.onSelectLayer,
                          onAdd: widget.onAddLayer,
                          onDelete: widget.onDeleteLayer,
                          onToggleVisibility: widget.onToggleVisibility,
                          onReorder: widget.onReorderLayers,
                          onTypeChanged: widget.onTypeChanged,
                          onShapeChanged: widget.onShapeChanged,
                          onInvertedChanged: widget.onInvertedChanged,
                          onIntensityChanged: widget.onIntensityChanged,
                          showTimeRange: widget.showTimeRange,
                          currentTime: widget.currentTime,
                          totalDuration: widget.totalDuration,
                          onSetStart: widget.onSetStart,
                          onSetEnd: widget.onSetEnd,
                          onSeekTo: widget.onSeekTo,
                          onAddKeyframeAtCurrent:
                              widget.onAddKeyframeAtCurrent,
                          onDeleteKeyframeAtCurrent:
                              widget.onDeleteKeyframeAtCurrent,
                          onDeleteKeyframe: widget.onDeleteKeyframe,
                        ),
                      ),
                    SizedBox(height: bottomInset > 0 ? bottomInset : 0),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return GestureDetector(
      onTap: _toggleExpand,
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null) {
          if (details.primaryDelta! > 5 && _expanded) {
            _toggleExpand();
          } else if (details.primaryDelta! < -5 && !_expanded) {
            _toggleExpand();
          }
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.spaceLg, 2, AppTheme.spaceSm, AppTheme.spaceSm),
      child: Row(
        children: [
          Icon(
            Icons.layers_rounded,
            size: 16,
            color: widget.layers.isEmpty
                ? AppTheme.textMuted
                : AppTheme.accentBright,
          ),
          const SizedBox(width: 8),
          Text(
            'レイヤー',
            style: AppTheme.textHeader.copyWith(fontSize: 15),
          ),
          const SizedBox(width: 6),
          if (widget.layers.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.bgHover,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${widget.layers.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          const Spacer(),
          if (!_expanded && widget.layers.isNotEmpty)
            GestureDetector(
              onTap: _expand,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.bgHover.withValues(alpha: 0.6),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('開く', style: AppTheme.textCaption),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 6),
          _AddButton(onTap: widget.onAddLayer),
        ],
      ),
    );
  }
}

class _AddButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.45),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '追加',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
