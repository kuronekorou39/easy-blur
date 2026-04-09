import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class LayerPanel extends StatelessWidget {
  final List<MosaicLayer> layers;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<int> onDelete;
  final ValueChanged<int> onToggleVisibility;
  final void Function(int oldIndex, int newIndex) onReorder;

  const LayerPanel({
    super.key,
    required this.layers,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onToggleVisibility,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgSecondary,
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'レイヤー',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                _SmallIconBtn(
                  icon: Icons.add_rounded,
                  onTap: onAdd,
                  tooltip: 'レイヤー追加',
                ),
              ],
            ),
          ),
          // Layer list
          if (layers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'レイヤーを追加してモザイクを配置',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: layers.length,
                onReorder: onReorder,
                itemBuilder: (context, index) {
                  final layer = layers[index];
                  final isSelected = index == selectedIndex;
                  return _LayerTile(
                    key: ValueKey(layer.id),
                    index: index,
                    layer: layer,
                    isSelected: isSelected,
                    onTap: () => onSelect(index),
                    onToggleVisibility: () => onToggleVisibility(index),
                    onDelete: () => onDelete(index),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LayerTile extends StatelessWidget {
  final int index;
  final MosaicLayer layer;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  const _LayerTile({
    super.key,
    required this.index,
    required this.layer,
    required this.isSelected,
    required this.onTap,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  IconData get _typeIcon {
    switch (layer.type) {
      case MosaicType.pixelate:
        return Icons.grid_on_rounded;
      case MosaicType.blur:
        return Icons.blur_on_rounded;
      case MosaicType.blackout:
        return Icons.block_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withAlpha(20)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppTheme.accent : Colors.transparent,
                width: 3,
              ),
              bottom: const BorderSide(color: AppTheme.borderColor, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(_typeIcon, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  layer.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _SmallIconBtn(
                icon: layer.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                onTap: onToggleVisibility,
                color: layer.visible ? AppTheme.textMuted : AppTheme.danger,
              ),
              _SmallIconBtn(
                icon: Icons.close_rounded,
                onTap: onDelete,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color color;

  const _SmallIconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = AppTheme.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
