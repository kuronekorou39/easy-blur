import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

/// 展開式レイヤーパネル
/// - 選択状態と展開状態は完全に独立
/// - 新規追加されたレイヤーは自動的に展開
/// - 展開はユーザーが矢印ボタンで自由に切り替え可能
class LayerPanel extends StatefulWidget {
  final List<MosaicLayer> layers;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onDelete;
  final ValueChanged<int> onToggleVisibility;
  final ValueChanged<int> onToggleLocked;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<bool> onInvertedChanged;
  final ValueChanged<int> onFillColorChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<double> onRotationChanged;
  final ValueChanged<double> onBarAngleChanged;

  // 動画用: 時間範囲編集
  final bool showTimeRange;
  final Duration? currentTime;
  final Duration? totalDuration;
  final ValueChanged<int>? onSetStart;
  final ValueChanged<int>? onSetEnd;
  final ValueChanged<Duration>? onSeekTo;
  final ValueChanged<int>? onAddKeyframeAtCurrent;
  final ValueChanged<int>? onDeleteKeyframeAtCurrent;
  final void Function(int layerIndex, int keyframeIndex)? onDeleteKeyframe;
  final ValueChanged<int>? onAddStylePointAtCurrent;
  final ValueChanged<int>? onDeleteStylePointAtCurrent;
  final void Function(int layerIndex, int styleIndex)? onDeleteStylePoint;
  final void Function(int layerIndex, int pointIndex, Offset position)?
      onSetPathPointPosition;

  const LayerPanel({
    super.key,
    required this.layers,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onToggleVisibility,
    required this.onToggleLocked,
    required this.onReorder,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onInvertedChanged,
    required this.onFillColorChanged,
    required this.onIntensityChanged,
    required this.onRotationChanged,
    required this.onBarAngleChanged,
    this.showTimeRange = false,
    this.currentTime,
    this.totalDuration,
    this.onSetStart,
    this.onSetEnd,
    this.onSeekTo,
    this.onAddKeyframeAtCurrent,
    this.onDeleteKeyframeAtCurrent,
    this.onDeleteKeyframe,
    this.onAddStylePointAtCurrent,
    this.onDeleteStylePointAtCurrent,
    this.onDeleteStylePoint,
    this.onSetPathPointPosition,
  });

  @override
  State<LayerPanel> createState() => _LayerPanelState();
}

class _LayerPanelState extends State<LayerPanel> {
  /// 展開中のレイヤーID
  final Set<String> _expandedIds = {};

  /// 「タイム」タブを表示中のレイヤーID（動画のみ。含まれなければ「見た目」タブ）
  final Set<String> _timeTabIds = {};

  /// 経路点一覧を展開中のレイヤーID（デフォルトは閉じておく）
  final Set<String> _pathListIds = {};

  /// 前回のレイヤーID（新規追加検出用）
  Set<String> _prevIds = {};

  @override
  void initState() {
    super.initState();
    _prevIds = widget.layers.map((l) => l.id).toSet();
  }

  @override
  void didUpdateWidget(covariant LayerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.layers.map((l) => l.id).toSet();
    // 新規追加されたレイヤーは自動展開
    final newIds = currentIds.difference(_prevIds);
    if (newIds.isNotEmpty) {
      _expandedIds.addAll(newIds);
    }
    // 削除されたレイヤーは展開状態から除去
    final removedIds = _prevIds.difference(currentIds);
    if (removedIds.isNotEmpty) {
      _expandedIds.removeAll(removedIds);
      _timeTabIds.removeAll(removedIds);
      _pathListIds.removeAll(removedIds);
    }
    _prevIds = currentIds;
  }

  void _togglePathList(String id) {
    setState(() {
      if (_pathListIds.contains(id)) {
        _pathListIds.remove(id);
      } else {
        _pathListIds.add(id);
      }
    });
  }

  void _setTimeTab(String id, bool isTimeTab) {
    setState(() {
      if (isTimeTab) {
        _timeTabIds.add(id);
      } else {
        _timeTabIds.remove(id);
      }
    });
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        return Column(
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bounded)
              Expanded(
                child: widget.layers.isEmpty
                    ? _buildEmptyState()
                    : _buildLayerList(bounded: true),
              )
            else
              widget.layers.isEmpty
                  ? SizedBox(height: 160, child: _buildEmptyState())
                  : _buildLayerList(bounded: false),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            ),
            child: Icon(
              Icons.layers_outlined,
              size: 32,
              color: AppTheme.textMuted.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          Text(
            'レイヤーがありません',
            style: AppTheme.textBodyStrong,
          ),
          const SizedBox(height: 4),
          Text(
            '右上の「追加」ボタンからモザイクを作成',
            style: AppTheme.textCaption,
          ),
        ],
      ),
    );
  }

  Widget _buildLayerList({required bool bounded}) {
    return Theme(
      data: ThemeData.dark().copyWith(
        canvasColor: Colors.transparent,
      ),
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.spaceSm, 0, AppTheme.spaceSm, AppTheme.spaceLg),
        buildDefaultDragHandles: false,
        shrinkWrap: !bounded,
        physics: bounded ? null : const ClampingScrollPhysics(),
        itemCount: widget.layers.length,
        onReorderItem: widget.onReorder,
        proxyDecorator: (child, index, animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(animation.value);
              return Material(
                color: Colors.transparent,
                elevation: 10 * t,
                shadowColor: Colors.black87,
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMedium),
                child: Transform.scale(
                  scale: 1.0 + 0.03 * t,
                  child: child,
                ),
              );
            },
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final layer = widget.layers[index];
          final isSelected = index == widget.selectedIndex;
          final isExpanded = _expandedIds.contains(layer.id);
          return _LayerTile(
            key: ValueKey(layer.id),
            index: index,
            layer: layer,
            isSelected: isSelected,
            isExpanded: isExpanded,
            isTimeTab: _timeTabIds.contains(layer.id),
            onTimeTabChanged: (v) => _setTimeTab(layer.id, v),
            onTap: () => widget.onSelect(index),
            onExpandToggle: () => _toggleExpand(layer.id),
            onToggleVisibility: () => widget.onToggleVisibility(index),
            onToggleLocked: () => widget.onToggleLocked(index),
            onDelete: () => widget.onDelete(index),
            onTypeChanged: (t) {
              widget.onSelect(index);
              widget.onTypeChanged(t);
            },
            onShapeChanged: (s) {
              widget.onSelect(index);
              widget.onShapeChanged(s);
            },
            onInvertedChanged: (v) {
              widget.onSelect(index);
              widget.onInvertedChanged(v);
            },
            onFillColorChanged: (c) {
              widget.onSelect(index);
              widget.onFillColorChanged(c);
            },
            onIntensityChanged: (v) {
              widget.onSelect(index);
              widget.onIntensityChanged(v);
            },
            onRotationChanged: (v) {
              widget.onSelect(index);
              widget.onRotationChanged(v);
            },
            onBarAngleChanged: (v) {
              widget.onSelect(index);
              widget.onBarAngleChanged(v);
            },
            showTimeRange: widget.showTimeRange,
            currentTime: widget.currentTime,
            totalDuration: widget.totalDuration,
            onSetStart: widget.onSetStart == null
                ? null
                : () => widget.onSetStart!(index),
            onSetEnd: widget.onSetEnd == null
                ? null
                : () => widget.onSetEnd!(index),
            onSeekTo: widget.onSeekTo,
            onAddKeyframeAtCurrent: widget.onAddKeyframeAtCurrent == null
                ? null
                : () => widget.onAddKeyframeAtCurrent!(index),
            onDeleteKeyframeAtCurrent:
                widget.onDeleteKeyframeAtCurrent == null
                    ? null
                    : () => widget.onDeleteKeyframeAtCurrent!(index),
            onDeleteKeyframe: widget.onDeleteKeyframe == null
                ? null
                : (kfIndex) => widget.onDeleteKeyframe!(index, kfIndex),
            onAddStylePointAtCurrent:
                widget.onAddStylePointAtCurrent == null
                    ? null
                    : () => widget.onAddStylePointAtCurrent!(index),
            onDeleteStylePointAtCurrent:
                widget.onDeleteStylePointAtCurrent == null
                    ? null
                    : () => widget.onDeleteStylePointAtCurrent!(index),
            onDeleteStylePoint: widget.onDeleteStylePoint == null
                ? null
                : (sIndex) => widget.onDeleteStylePoint!(index, sIndex),
            isPathListExpanded: _pathListIds.contains(layer.id),
            onPathListToggle: () => _togglePathList(layer.id),
            onSetPathPointPosition:
                widget.onSetPathPointPosition == null
                    ? null
                    : (pIndex, pos) =>
                        widget.onSetPathPointPosition!(index, pIndex, pos),
          );
        },
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  final int index;
  final MosaicLayer layer;
  final bool isSelected;
  final bool isExpanded;
  final bool isTimeTab;
  final ValueChanged<bool> onTimeTabChanged;
  final VoidCallback onTap;
  final VoidCallback onExpandToggle;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleLocked;
  final VoidCallback onDelete;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<bool> onInvertedChanged;
  final ValueChanged<int> onFillColorChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<double> onRotationChanged;
  final ValueChanged<double> onBarAngleChanged;

  // 動画用
  final bool showTimeRange;
  final Duration? currentTime;
  final Duration? totalDuration;
  final VoidCallback? onSetStart;
  final VoidCallback? onSetEnd;
  final ValueChanged<Duration>? onSeekTo;
  final VoidCallback? onAddKeyframeAtCurrent;
  final VoidCallback? onDeleteKeyframeAtCurrent;
  final ValueChanged<int>? onDeleteKeyframe;
  final VoidCallback? onAddStylePointAtCurrent;
  final VoidCallback? onDeleteStylePointAtCurrent;
  final ValueChanged<int>? onDeleteStylePoint;
  final bool isPathListExpanded;
  final VoidCallback? onPathListToggle;
  final void Function(int pointIndex, Offset position)?
      onSetPathPointPosition;

  const _LayerTile({
    super.key,
    required this.index,
    required this.layer,
    required this.isSelected,
    required this.isExpanded,
    required this.isTimeTab,
    required this.onTimeTabChanged,
    required this.onTap,
    required this.onExpandToggle,
    required this.onToggleVisibility,
    required this.onToggleLocked,
    required this.onDelete,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onInvertedChanged,
    required this.onFillColorChanged,
    required this.onIntensityChanged,
    required this.onRotationChanged,
    required this.onBarAngleChanged,
    this.showTimeRange = false,
    this.currentTime,
    this.totalDuration,
    this.onSetStart,
    this.onSetEnd,
    this.onSeekTo,
    this.onAddKeyframeAtCurrent,
    this.onDeleteKeyframeAtCurrent,
    this.onDeleteKeyframe,
    this.onAddStylePointAtCurrent,
    this.onDeleteStylePointAtCurrent,
    this.onDeleteStylePoint,
    this.isPathListExpanded = false,
    this.onPathListToggle,
    this.onSetPathPointPosition,
  });

  IconData get _typeIcon {
    switch (layer.type) {
      case MosaicType.pixelate:
        return Icons.grid_on_rounded;
      case MosaicType.blur:
        return Icons.blur_on_rounded;
      case MosaicType.fill:
        return Icons.format_color_fill_rounded;
      case MosaicType.noise:
        return Icons.grain_rounded;
      case MosaicType.bars:
        return Icons.view_stream_rounded;
    }
  }

  String get _typeLabel {
    switch (layer.type) {
      case MosaicType.pixelate:
        return 'モザイク';
      case MosaicType.blur:
        return 'ぼかし';
      case MosaicType.fill:
        return 'バケツ';
      case MosaicType.noise:
        return 'ノイズ';
      case MosaicType.bars:
        return '黒のり';
    }
  }

  String get _shapeLabel {
    switch (layer.shape) {
      case MosaicShape.rectangle:
        return '矩形';
      case MosaicShape.ellipse:
        return '楕円';
      case MosaicShape.triangle:
        return '三角';
      case MosaicShape.heart:
        return 'ハート';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 表示値は現在時刻の補間状態（画像は時刻ゼロ固定）
    final state = layer.getStateAt(currentTime ?? Duration.zero);
    final intensity = state.intensity.round();

    return Padding(
      key: ValueKey('pad_${layer.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: AppTheme.animFast,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.12)
                : AppTheme.bgTertiary.withValues(alpha: 0.5),
            borderRadius:
                BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accent.withValues(alpha: 0.7)
                  : AppTheme.borderColor.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(intensity),
              AnimatedSize(
                duration: AppTheme.animNormal,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: isExpanded
                    // 高さに上限を設けて中でスクロールさせる。
                    // 縦に伸びすぎて他のレイヤーが隠れるのを防ぐ
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              (MediaQuery.of(context).size.height * 0.34)
                                  .clamp(240.0, 360.0),
                        ),
                        child: SingleChildScrollView(
                          child: _buildExpandedProperties(state),
                        ),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int intensity) {
    return Row(
      children: [
        // ドラッグハンドル
        ReorderableDragStartListener(
          index: index,
          child: Container(
            width: 32,
            height: 48,
            alignment: Alignment.center,
            child: Icon(
              Icons.drag_indicator_rounded,
              size: 18,
              color: AppTheme.textMuted.withValues(alpha: 0.7),
            ),
          ),
        ),
        // タップ可能な中央領域（選択のみ、展開しない）
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent.withValues(alpha: 0.3)
                          : AppTheme.bgHover,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Icon(
                      _typeIcon,
                      size: 18,
                      color: isSelected
                          ? AppTheme.accentBright
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceMd),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          layer.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: layer.visible
                                ? AppTheme.textPrimary
                                : AppTheme.textMuted,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$_typeLabel · $_shapeLabel · $intensity',
                                style: AppTheme.textCaption
                                    .copyWith(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // 動画: 現在時刻が表示範囲外なら明示
                            if (showTimeRange &&
                                currentTime != null &&
                                !layer.isActiveAt(currentTime!)) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.warning
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppTheme.warning
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Text(
                                  '範囲外',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.warning,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ロック/解除
        _IconAction(
          icon: layer.locked
              ? Icons.lock_rounded
              : Icons.lock_open_rounded,
          color: layer.locked
              ? AppTheme.accentBright
              : AppTheme.textMuted,
          tooltip: layer.locked ? 'ロック解除' : 'ロック',
          onTap: onToggleLocked,
        ),
        // 表示/非表示
        _IconAction(
          icon: layer.visible
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          color: layer.visible
              ? AppTheme.textSecondary
              : AppTheme.danger,
          tooltip: layer.visible ? '非表示' : '表示',
          onTap: onToggleVisibility,
        ),
        _IconAction(
          icon: Icons.delete_outline_rounded,
          color: AppTheme.textMuted,
          tooltip: '削除',
          onTap: onDelete,
        ),
        // 展開トグル（独立）
        _ExpandToggle(
          isExpanded: isExpanded,
          onTap: onExpandToggle,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  String _shapeName(MosaicShape s) {
    switch (s) {
      case MosaicShape.rectangle:
        return '矩形';
      case MosaicShape.ellipse:
        return '楕円';
      case MosaicShape.triangle:
        return '三角';
      case MosaicShape.heart:
        return 'ハート';
    }
  }

  IconData _shapeIconOf(MosaicShape s) {
    switch (s) {
      case MosaicShape.rectangle:
        return Icons.crop_square_rounded;
      case MosaicShape.ellipse:
        return Icons.circle_outlined;
      case MosaicShape.triangle:
        return Icons.change_history_rounded;
      case MosaicShape.heart:
        return Icons.favorite_outline_rounded;
    }
  }

  /// 黒のり用：バーの角度（-90°〜+90°）
  Widget _buildBarAngleSection() {
    final rad = layer.barAngle;
    final deg = (rad * 180 / 3.14159265358979).round().clamp(-90, 90);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('バー角度', style: AppTheme.textLabel),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Text(
                '$deg°',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentBright,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => onBarAngleChanged(0.0),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bgHover.withValues(alpha: 0.6),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(
                    color: AppTheme.borderColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 3),
                    Text(
                      'リセット',
                      style:
                          AppTheme.textCaption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            _SliderButton(
              icon: Icons.remove_rounded,
              onTap: () => onBarAngleChanged(
                ((deg - 1).clamp(-90, 90)) * 3.14159265358979 / 180,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                value: deg.toDouble().clamp(-90, 90),
                min: -90,
                max: 90,
                divisions: 180,
                onChanged: (v) =>
                    onBarAngleChanged(v * 3.14159265358979 / 180),
              ),
            ),
            const SizedBox(width: 4),
            _SliderButton(
              icon: Icons.add_rounded,
              onTap: () => onBarAngleChanged(
                ((deg + 1).clamp(-90, 90)) * 3.14159265358979 / 180,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRotationSection(double rotationRad) {
    // ラジアン → 度
    final deg = (rotationRad * 180 / 3.14159265358979).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('回転', style: AppTheme.textLabel),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Text(
                '$deg°',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentBright,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => onRotationChanged(0.0),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bgHover.withValues(alpha: 0.6),
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(
                    color: AppTheme.borderColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 3),
                    Text(
                      'リセット',
                      style: AppTheme.textCaption
                          .copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            _SliderButton(
              icon: Icons.remove_rounded,
              onTap: () => onRotationChanged(
                ((deg - 1).clamp(-180, 180)) * 3.14159265358979 / 180,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                value: deg.toDouble().clamp(-180, 180),
                min: -180,
                max: 180,
                divisions: 360,
                onChanged: (v) =>
                    onRotationChanged(v * 3.14159265358979 / 180),
              ),
            ),
            const SizedBox(width: 4),
            _SliderButton(
              icon: Icons.add_rounded,
              onTap: () => onRotationChanged(
                ((deg + 1).clamp(-180, 180)) * 3.14159265358979 / 180,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// バケツ用色プリセット（システムカラー風 8色）
  static const List<int> _colorPresets = [
    0xFF000000, // 黒
    0xFFFFFFFF, // 白
    0xFFFF3B30, // 赤
    0xFFFF9500, // オレンジ
    0xFFFFCC00, // 黄
    0xFF34C759, // 緑
    0xFF007AFF, // 青
    0xFFAF52DE, // 紫
  ];

  Widget _buildColorPalette() {
    return Row(
      children: [
        for (int i = 0; i < _colorPresets.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => onFillColorChanged(_colorPresets[i]),
              behavior: HitTestBehavior.opaque,
              child: AspectRatio(
                aspectRatio: 1,
                child: AnimatedContainer(
                  duration: AppTheme.animFast,
                  decoration: BoxDecoration(
                    color: Color(_colorPresets[i]),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(
                      color: layer.fillColor == _colorPresets[i]
                          ? AppTheme.accentBright
                          : Colors.white.withValues(alpha: 0.15),
                      width: layer.fillColor == _colorPresets[i] ? 2.5 : 1,
                    ),
                    boxShadow: layer.fillColor == _colorPresets[i]
                        ? [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: -1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeGrid() {
    // 4種の効果を 1行 4列で表示
    final types = MosaicType.values;
    return Row(
      children: [
        for (int i = 0; i < types.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _OptionChip(
              label: _labelForType(types[i]),
              icon: _iconForType(types[i]),
              isSelected: layer.type == types[i],
              onTap: () => onTypeChanged(types[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpandedProperties(LayerState state) {
    // 動画では「見た目」と「タイム」をタブで分割し、縦長になるのを防ぐ
    final hasTimeTab =
        showTimeRange && totalDuration != null && currentTime != null;
    final showTimeContent = hasTimeTab && isTimeTab;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            color: AppTheme.borderColor.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          if (hasTimeTab) ...[
            _PropTabSwitcher(
              isTimeTab: isTimeTab,
              keyframeCount: layer.pathKeyframes.length,
              onChanged: onTimeTabChanged,
            ),
            const SizedBox(height: AppTheme.spaceMd),
          ],
          if (showTimeContent)
            _TimeRangeControl(
              startTime: layer.startTime,
              endTime: _effectiveEnd(layer.endTime, totalDuration!),
              currentTime: currentTime!,
              totalDuration: totalDuration!,
              keyframeTimes:
                  layer.pathKeyframes.map((k) => k.time).toList(),
              styleTimes:
                  layer.styleKeyframes.map((s) => s.time).toList(),
              pathPoints: layer.pathKeyframes,
              isPathListExpanded: isPathListExpanded,
              onPathListToggle: onPathListToggle,
              onSetPathPointPosition: onSetPathPointPosition,
              onSetStart: onSetStart,
              onSetEnd: onSetEnd,
              onSeekTo: onSeekTo,
              onAddKeyframeAtCurrent: onAddKeyframeAtCurrent,
              onDeleteKeyframeAtCurrent: onDeleteKeyframeAtCurrent,
              onDeleteKeyframe: onDeleteKeyframe,
              onAddStylePointAtCurrent: onAddStylePointAtCurrent,
              onDeleteStylePointAtCurrent: onDeleteStylePointAtCurrent,
              onDeleteStylePoint: onDeleteStylePoint,
              isActive: layer.isActiveAt(currentTime!),
            )
          else
            _buildLookProperties(state),
        ],
      ),
    );
  }

  /// 「見た目」タブ: 効果・色・形状・強度・回転
  Widget _buildLookProperties(LayerState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('効果', style: AppTheme.textLabel),
        const SizedBox(height: 6),
        _buildTypeGrid(),
        // バケツ・黒のり選択時に色プリセットを表示
        if (layer.type == MosaicType.fill ||
            layer.type == MosaicType.bars) ...[
          const SizedBox(height: AppTheme.spaceMd),
          Row(
            children: [
              Text('色', style: AppTheme.textLabel),
              const SizedBox(width: 8),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Color(layer.fillColor),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppTheme.borderLight.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildColorPalette(),
        ],
        // 黒のり選択時はバー角度スライダー
        if (layer.type == MosaicType.bars) ...[
          const SizedBox(height: AppTheme.spaceMd),
          _buildBarAngleSection(),
        ],
        const SizedBox(height: AppTheme.spaceMd),
        // 形状ヘッダー（右端に内側/外側トグル）
        Row(
          children: [
            Text('形状', style: AppTheme.textLabel),
            const Spacer(),
            _InvertToggle(
              isInverted: layer.inverted,
              onTap: () => onInvertedChanged(!layer.inverted),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 0; i < MosaicShape.values.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _OptionChip(
                  label: _shapeName(MosaicShape.values[i]),
                  icon: _shapeIconOf(MosaicShape.values[i]),
                  isSelected: layer.shape == MosaicShape.values[i],
                  onTap: () => onShapeChanged(MosaicShape.values[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('強度', style: AppTheme.textLabel),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Text(
                '${state.intensity.round()}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentBright,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            _SliderButton(
              icon: Icons.remove_rounded,
              onTap: () {
                onIntensityChanged(
                    (state.intensity - 2).clamp(2, 60));
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                value: state.intensity.clamp(2, 60),
                min: 2,
                max: 60,
                onChanged: onIntensityChanged,
              ),
            ),
            const SizedBox(width: 4),
            _SliderButton(
              icon: Icons.add_rounded,
              onTap: () {
                onIntensityChanged(
                    (state.intensity + 2).clamp(2, 60));
              },
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        // 回転セクション
        _buildRotationSection(state.rotation),
      ],
    );
  }

  Duration _effectiveEnd(Duration layerEnd, Duration totalDuration) {
    // endTime の初期値が days: 1 の場合は、動画の終端に丸める
    return layerEnd > totalDuration ? totalDuration : layerEnd;
  }

  String _labelForType(MosaicType t) {
    switch (t) {
      case MosaicType.pixelate:
        return 'モザイク';
      case MosaicType.blur:
        return 'ぼかし';
      case MosaicType.fill:
        return 'バケツ';
      case MosaicType.noise:
        return 'ノイズ';
      case MosaicType.bars:
        return '黒のり';
    }
  }

  IconData _iconForType(MosaicType t) {
    switch (t) {
      case MosaicType.pixelate:
        return Icons.grid_on_rounded;
      case MosaicType.blur:
        return Icons.blur_on_rounded;
      case MosaicType.fill:
        return Icons.format_color_fill_rounded;
      case MosaicType.noise:
        return Icons.grain_rounded;
      case MosaicType.bars:
        return Icons.view_stream_rounded;
    }
  }

}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 40,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: color),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _ExpandToggle extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _ExpandToggle({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isExpanded ? 'プロパティを閉じる' : 'プロパティを開く',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isExpanded
                ? AppTheme.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: AnimatedRotation(
            duration: AppTheme.animFast,
            turns: isExpanded ? 0.5 : 0.0,
            child: Icon(
              Icons.expand_more_rounded,
              size: 22,
              color: isExpanded
                  ? AppTheme.accentBright
                  : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 動画専用: 展開プロパティの「見た目 / タイム」タブ切替
class _PropTabSwitcher extends StatelessWidget {
  final bool isTimeTab;
  final int keyframeCount;
  final ValueChanged<bool> onChanged;

  const _PropTabSwitcher({
    required this.isTimeTab,
    required this.keyframeCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.bgTertiary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 3),
        border: Border.all(
            color: AppTheme.borderColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PropTabSegment(
              icon: Icons.palette_outlined,
              label: '見た目',
              isSelected: !isTimeTab,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _PropTabSegment(
              icon: Icons.schedule_rounded,
              label: 'タイム',
              badge: keyframeCount > 1 ? '$keyframeCount' : null,
              isSelected: isTimeTab,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropTabSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool isSelected;
  final VoidCallback onTap;

  const _PropTabSegment({
    required this.icon,
    required this.label,
    this.badge,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.7)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? AppTheme.accentBright
                  : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.accent.withValues(alpha: 0.4)
                      : AppTheme.bgHover,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 動画専用: レイヤーの表示時間範囲コントロール
class _TimeRangeControl extends StatelessWidget {
  final Duration startTime;
  final Duration endTime;
  final Duration currentTime;
  final Duration totalDuration;
  final List<Duration> keyframeTimes;
  final List<Duration> styleTimes;

  /// 経路点の実データ（一覧の手動調整用）
  final List<PathPoint> pathPoints;
  final bool isPathListExpanded;
  final VoidCallback? onPathListToggle;
  final void Function(int pointIndex, Offset position)?
      onSetPathPointPosition;
  final VoidCallback? onSetStart;
  final VoidCallback? onSetEnd;
  final ValueChanged<Duration>? onSeekTo;
  final VoidCallback? onAddKeyframeAtCurrent;
  final VoidCallback? onDeleteKeyframeAtCurrent;
  final ValueChanged<int>? onDeleteKeyframe;
  final VoidCallback? onAddStylePointAtCurrent;
  final VoidCallback? onDeleteStylePointAtCurrent;
  final ValueChanged<int>? onDeleteStylePoint;
  final bool isActive;

  const _TimeRangeControl({
    required this.startTime,
    required this.endTime,
    required this.currentTime,
    required this.totalDuration,
    required this.keyframeTimes,
    required this.styleTimes,
    required this.pathPoints,
    required this.isPathListExpanded,
    required this.onPathListToggle,
    required this.onSetPathPointPosition,
    required this.onSetStart,
    required this.onSetEnd,
    required this.onSeekTo,
    required this.onAddKeyframeAtCurrent,
    required this.onDeleteKeyframeAtCurrent,
    required this.onDeleteKeyframe,
    required this.onAddStylePointAtCurrent,
    required this.onDeleteStylePointAtCurrent,
    required this.onDeleteStylePoint,
    required this.isActive,
  });

  /// 現在時刻に一致する時刻があるかチェック（インデックスを返す、なければ-1）
  int _findAtCurrent(List<Duration> times) {
    const toleranceMs = 150;
    for (int i = 0; i < times.length; i++) {
      if ((times[i].inMilliseconds - currentTime.inMilliseconds).abs() <=
          toleranceMs) {
        return i;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final hasKfAtCurrent = _findAtCurrent(keyframeTimes) >= 0;
    final hasStyleAtCurrent = _findAtCurrent(styleTimes) >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('表示範囲', style: AppTheme.textLabel),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.success
                    : AppTheme.textMuted.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isActive ? '表示中' : '非表示',
              style: AppTheme.textCaption.copyWith(
                fontSize: 10,
                color: isActive
                    ? AppTheme.success
                    : AppTheme.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _RangeBar(
          startTime: startTime,
          endTime: endTime,
          currentTime: currentTime,
          totalDuration: totalDuration,
          keyframeTimes: keyframeTimes,
          styleTimes: styleTimes,
          onSeekTo: onSeekTo,
          onDeleteKeyframe: onDeleteKeyframe,
          onDeleteStylePoint: onDeleteStylePoint,
        ),
        const SizedBox(height: 10),
        // 開始・終了行
        Row(
          children: [
            Expanded(
              child: _TimeBlock(
                label: '開始',
                time: startTime,
                color: AppTheme.accent,
                onSetHere: onSetStart,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TimeBlock(
                label: '終了',
                time: endTime,
                color: AppTheme.accentBright,
                onSetHere: onSetEnd,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Container(
          height: 1,
          color: AppTheme.borderColor.withValues(alpha: 0.4),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        // 経路（移動キーフレーム）管理
        _TrackHeader(
          label: '経路（移動）',
          count: keyframeTimes.length,
          markerColor: AppTheme.accentBright,
          atCurrent: hasKfAtCurrent,
          trailing: onPathListToggle == null || pathPoints.isEmpty
              ? null
              : _ListToggleChip(
                  isExpanded: isPathListExpanded,
                  onTap: onPathListToggle!,
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _KeyframeActionButton(
                icon: Icons.add_location_alt_rounded,
                label: 'ここに追加',
                accent: true,
                enabled: !hasKfAtCurrent && onAddKeyframeAtCurrent != null,
                onTap: onAddKeyframeAtCurrent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KeyframeActionButton(
                icon: Icons.wrong_location_rounded,
                label: 'ここを削除',
                accent: false,
                enabled: hasKfAtCurrent &&
                    keyframeTimes.length > 1 &&
                    onDeleteKeyframeAtCurrent != null,
                onTap: onDeleteKeyframeAtCurrent,
              ),
            ),
          ],
        ),
        // 経路点の一覧（必要なときだけ開く。座標の手動微調整用）
        AnimatedSize(
          duration: AppTheme.animNormal,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isPathListExpanded && pathPoints.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _PathPointList(
                    points: pathPoints,
                    currentTime: currentTime,
                    onSeekTo: onSeekTo,
                    onSetPosition: onSetPathPointPosition,
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        // 基準（サイズ・強度・回転キーフレーム）管理
        _TrackHeader(
          label: '基準（サイズ・強度）',
          count: styleTimes.length,
          markerColor: AppTheme.warning,
          atCurrent: hasStyleAtCurrent,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _KeyframeActionButton(
                icon: Icons.add_location_alt_rounded,
                label: 'ここに追加',
                accent: true,
                enabled: !hasStyleAtCurrent &&
                    onAddStylePointAtCurrent != null,
                onTap: onAddStylePointAtCurrent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _KeyframeActionButton(
                icon: Icons.wrong_location_rounded,
                label: 'ここを削除',
                accent: false,
                enabled: hasStyleAtCurrent &&
                    styleTimes.length > 1 &&
                    onDeleteStylePointAtCurrent != null,
                onTap: onDeleteStylePointAtCurrent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'バーの丸=経路・ひし形=基準。タップで移動、長押しで削除',
          style: AppTheme.textCaption.copyWith(fontSize: 10),
        ),
      ],
    );
  }
}

/// 経路/基準トラックの見出し行（ラベル + 個数 + 現在位置バッジ）
class _TrackHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color markerColor;
  final bool atCurrent;
  final Widget? trailing;

  const _TrackHeader({
    required this.label,
    required this.count,
    required this.markerColor,
    required this.atCurrent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppTheme.textLabel),
        const SizedBox(width: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.bgHover,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
        const Spacer(),
        if (atCurrent)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: markerColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: markerColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '現在位置にあり',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: markerColor,
                  ),
                ),
              ],
            ),
          ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing!,
        ],
      ],
    );
  }
}

/// 一覧の開閉チップ（経路点リスト用）
class _ListToggleChip extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _ListToggleChip({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isExpanded
              ? AppTheme.accent.withValues(alpha: 0.2)
              : AppTheme.bgHover.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isExpanded
                ? AppTheme.accent.withValues(alpha: 0.6)
                : AppTheme.borderColor.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_list_numbered_rounded,
              size: 12,
              color: isExpanded
                  ? AppTheme.accentBright
                  : AppTheme.textMuted,
            ),
            const SizedBox(width: 3),
            Text(
              '一覧',
              style: AppTheme.textCaption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isExpanded
                    ? AppTheme.accentBright
                    : AppTheme.textSecondary,
              ),
            ),
            AnimatedRotation(
              duration: AppTheme.animFast,
              turns: isExpanded ? 0.5 : 0.0,
              child: Icon(
                Icons.expand_more_rounded,
                size: 13,
                color: isExpanded
                    ? AppTheme.accentBright
                    : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 経路点の一覧。各点の時刻表示・シーク・X/Y の手動調整
class _PathPointList extends StatelessWidget {
  final List<PathPoint> points;
  final Duration currentTime;
  final ValueChanged<Duration>? onSeekTo;
  final void Function(int index, Offset position)? onSetPosition;

  const _PathPointList({
    required this.points,
    required this.currentTime,
    required this.onSeekTo,
    required this.onSetPosition,
  });

  static String _fmtTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final f = (d.inMilliseconds % 1000) ~/ 100;
    return '$m:${s.toString().padLeft(2, '0')}.$f';
  }

  /// 現在時刻に最も近い点（150ms以内）を強調表示する
  int _activeIndex() {
    for (int i = 0; i < points.length; i++) {
      if ((points[i].time.inMilliseconds - currentTime.inMilliseconds)
              .abs() <=
          150) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _editValue(
    BuildContext context, {
    required int index,
    required bool isX,
  }) async {
    final point = points[index];
    final current = isX ? point.position.dx : point.position.dy;
    final controller =
        TextEditingController(text: current.round().toString());
    final entered = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text('${isX ? 'X' : 'Y'} 座標を入力'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTheme.textBody,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.bgTertiary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
            ),
            child: const Text('設定'),
          ),
        ],
      ),
    );
    if (entered != null) {
      final pos = point.position;
      onSetPosition?.call(
        index,
        isX ? Offset(entered, pos.dy) : Offset(pos.dx, entered),
      );
    }
  }

  void _nudge(int index, bool isX, double delta) {
    final pos = points[index].position;
    onSetPosition?.call(
      index,
      isX
          ? Offset(pos.dx + delta, pos.dy)
          : Offset(pos.dx, pos.dy + delta),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgTertiary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
            color: AppTheme.borderColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < points.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                color: AppTheme.borderColor.withValues(alpha: 0.25),
              ),
            _buildRow(context, i, isActive: i == active),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Text(
              '時刻タップでシーク、± で1ずつ（長押しで10ずつ）、数値タップで直接入力',
              style: AppTheme.textCaption.copyWith(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, int index,
      {required bool isActive}) {
    final point = points[index];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          // 時刻（タップでシーク）
          GestureDetector(
            onTap:
                onSeekTo == null ? null : () => onSeekTo!(point.time),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.accentBright
                          : AppTheme.textMuted.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _fmtTime(point.time),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive
                          ? AppTheme.accentBright
                          : AppTheme.textSecondary,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _buildAxisCluster(context, index, isX: true),
          const SizedBox(width: 8),
          _buildAxisCluster(context, index, isX: false),
        ],
      ),
    );
  }

  Widget _buildAxisCluster(BuildContext context, int index,
      {required bool isX}) {
    final point = points[index];
    final value = isX ? point.position.dx : point.position.dy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isX ? 'X' : 'Y',
          style: AppTheme.textCaption.copyWith(fontSize: 9),
        ),
        const SizedBox(width: 3),
        _NudgeButton(
          icon: Icons.remove_rounded,
          onTap: () => _nudge(index, isX, -1),
          onLongPress: () => _nudge(index, isX, -10),
        ),
        GestureDetector(
          onTap: onSetPosition == null
              ? null
              : () => _editValue(context, index: index, isX: isX),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            child: Text(
              '${value.round()}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        _NudgeButton(
          icon: Icons.add_rounded,
          onTap: () => _nudge(index, isX, 1),
          onLongPress: () => _nudge(index, isX, 10),
        ),
      ],
    );
  }
}

/// 経路点一覧の ± ボタン（タップ±1、長押し±10）
class _NudgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _NudgeButton({
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppTheme.bgHover.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppTheme.borderColor.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, size: 14, color: AppTheme.textSecondary),
      ),
    );
  }
}

class _KeyframeActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final bool enabled;
  final VoidCallback? onTap;

  const _KeyframeActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppTheme.accent : AppTheme.danger;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: AppTheme.animFast,
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: enabled ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: color.withValues(alpha: enabled ? 0.55 : 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  final Duration startTime;
  final Duration endTime;
  final Duration currentTime;
  final Duration totalDuration;

  /// 経路キーフレーム時刻（丸マーカー、上段）
  final List<Duration> keyframeTimes;

  /// 基準時刻（ひし形マーカー、下段）
  final List<Duration> styleTimes;
  final ValueChanged<Duration>? onSeekTo;
  final ValueChanged<int>? onDeleteKeyframe;
  final ValueChanged<int>? onDeleteStylePoint;

  const _RangeBar({
    required this.startTime,
    required this.endTime,
    required this.currentTime,
    required this.totalDuration,
    required this.keyframeTimes,
    required this.styleTimes,
    required this.onSeekTo,
    this.onDeleteKeyframe,
    this.onDeleteStylePoint,
  });

  Future<void> _confirmDelete(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirmed,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Text(title),
        content: Text(message, style: AppTheme.textBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onConfirmed();
    }
  }

  /// 現在時刻と一致（200ms誤差内）する時刻のインデックス
  int? _activeIndex(List<Duration> times) {
    for (int i = 0; i < times.length; i++) {
      if ((times[i].inMilliseconds - currentTime.inMilliseconds).abs() <
          200) {
        return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final total = totalDuration.inMilliseconds.toDouble();
    if (total <= 0) return const SizedBox(height: 46);
    final startPct = (startTime.inMilliseconds / total).clamp(0.0, 1.0);
    final endPct = (endTime.inMilliseconds / total).clamp(0.0, 1.0);
    final curPct = (currentTime.inMilliseconds / total).clamp(0.0, 1.0);

    final activeKfIndex = _activeIndex(keyframeTimes);
    final activeStyleIndex = _activeIndex(styleTimes);

    return SizedBox(
      height: 46,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 背景トラック (タップでシーク)
              Positioned(
                left: 0,
                right: 0,
                top: 14,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: onSeekTo == null
                      ? null
                      : (details) {
                          final box = context.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local = box.globalToLocal(details.globalPosition);
                          final pct = (local.dx / w).clamp(0.0, 1.0);
                          onSeekTo!(Duration(
                              milliseconds: (pct * total).round()));
                        },
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.bgHover,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // アクティブ範囲
              Positioned(
                left: startPct * w,
                top: 12,
                child: IgnorePointer(
                  child: Container(
                    width: ((endPct - startPct) * w).clamp(0.0, w),
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentBright],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 経路マーカー（丸、トラック上段）
              for (int i = 0; i < keyframeTimes.length; i++)
                Positioned(
                  left: ((keyframeTimes[i].inMilliseconds / total)
                              .clamp(0.0, 1.0) *
                          w) -
                      12,
                  top: 4,
                  width: 24,
                  height: 24,
                  child: GestureDetector(
                    onTap: onSeekTo == null
                        ? null
                        : () => onSeekTo!(keyframeTimes[i]),
                    onLongPress: onDeleteKeyframe == null ||
                            keyframeTimes.length <= 1
                        ? null
                        : () => _confirmDelete(
                              context,
                              title: '経路キーフレームを削除',
                              message:
                                  'この時刻の経路キーフレームを削除します。\nモザイクの動きが変わります。',
                              onConfirmed: () => onDeleteKeyframe!(i),
                            ),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: AnimatedContainer(
                        duration: AppTheme.animFast,
                        width: activeKfIndex == i ? 12 : 9,
                        height: activeKfIndex == i ? 12 : 9,
                        decoration: BoxDecoration(
                          color: activeKfIndex == i
                              ? AppTheme.accentBright
                              : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: activeKfIndex == i
                                ? Colors.white
                                : AppTheme.accent,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.6),
                              blurRadius: activeKfIndex == i ? 8 : 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // 基準マーカー（ひし形、トラック下段）
              for (int i = 0; i < styleTimes.length; i++)
                Positioned(
                  left: ((styleTimes[i].inMilliseconds / total)
                              .clamp(0.0, 1.0) *
                          w) -
                      11,
                  top: 24,
                  width: 22,
                  height: 22,
                  child: GestureDetector(
                    onTap: onSeekTo == null
                        ? null
                        : () => onSeekTo!(styleTimes[i]),
                    onLongPress: onDeleteStylePoint == null ||
                            styleTimes.length <= 1
                        ? null
                        : () => _confirmDelete(
                              context,
                              title: '基準を削除',
                              message:
                                  'この時刻の基準を削除します。\nサイズ・強度の変化が変わります。',
                              onConfirmed: () => onDeleteStylePoint!(i),
                            ),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Transform.rotate(
                        angle: 0.7853981633974483, // 45度
                        child: AnimatedContainer(
                          duration: AppTheme.animFast,
                          width: activeStyleIndex == i ? 10 : 8,
                          height: activeStyleIndex == i ? 10 : 8,
                          decoration: BoxDecoration(
                            color: activeStyleIndex == i
                                ? AppTheme.warning
                                : Colors.white,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: activeStyleIndex == i
                                  ? Colors.white
                                  : AppTheme.warning,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.warning
                                    .withValues(alpha: 0.6),
                                blurRadius:
                                    activeStyleIndex == i ? 8 : 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // 現在位置インジケーター（縦ライン）
              Positioned(
                left: (curPct * w) - 1.5,
                top: 6,
                child: IgnorePointer(
                  child: Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
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
            ],
          );
        },
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final String label;
  final Duration time;
  final Color color;
  final VoidCallback? onSetHere;

  const _TimeBlock({
    required this.label,
    required this.time,
    required this.color,
    required this.onSetHere,
  });

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final ms = (d.inMilliseconds % 1000) ~/ 100;
    return '$m:${s.toString().padLeft(2, '0')}.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spaceSm),
      decoration: BoxDecoration(
        color: AppTheme.bgTertiary.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
            color: AppTheme.borderColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTheme.textCaption.copyWith(fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _format(time),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onSetHere,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.my_location_rounded, size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(
                    '今ここ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SliderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppTheme.bgTertiary,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
              color: AppTheme.borderColor.withValues(alpha: 0.5)),
        ),
        child: Icon(icon, size: 17, color: AppTheme.textSecondary),
      ),
    );
  }
}

/// 「内側 ⇄ 外側」を切り替える小さなトグルチップ
class _InvertToggle extends StatelessWidget {
  final bool isInverted;
  final VoidCallback onTap;

  const _InvertToggle({required this.isInverted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = isInverted ? '外側' : '内側';
    final icon = isInverted
        ? Icons.filter_center_focus_rounded
        : Icons.center_focus_strong_rounded;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: 'タップで内側⇄外側を切替',
        child: AnimatedContainer(
          duration: AppTheme.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isInverted
                ? AppTheme.accent.withValues(alpha: 0.2)
                : AppTheme.bgHover.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: isInverted
                  ? AppTheme.accent.withValues(alpha: 0.6)
                  : AppTheme.borderColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isInverted
                    ? AppTheme.accentBright
                    : AppTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isInverted
                      ? AppTheme.accentBright
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.25)
              : AppTheme.bgTertiary,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected
                ? AppTheme.accent
                : AppTheme.borderColor.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AppTheme.accentBright
                  : AppTheme.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
