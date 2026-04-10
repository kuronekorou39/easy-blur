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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
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
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.bgTertiary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${layers.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              _AddLayerBtn(onTap: onAdd),
            ],
          ),
        ),
        // Layer list
        if (layers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined,
                      size: 28, color: AppTheme.textMuted.withValues(alpha:0.3)),
                  const SizedBox(height: 6),
                  Text(
                    'レイヤーを追加してモザイクを配置',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted.withValues(alpha:0.5),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: layers.length,
              onReorder: onReorder,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final t = Curves.easeOut.transform(animation.value);
                    return Material(
                      color: Colors.transparent,
                      elevation: 8 * t,
                      shadowColor: Colors.black54,
                      child: Transform.scale(
                        scale: 1.0 + 0.02 * t,
                        child: child,
                      ),
                    );
                  },
                  child: child,
                );
              },
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
    return Dismissible(
      key: ValueKey('dismiss_${layer.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.danger.withValues(alpha:0.2),
        child: const Icon(Icons.delete_rounded,
            color: AppTheme.danger, size: 20),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => onDelete(),
      child: ReorderableDragStartListener(
        index: index,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.accent.withAlpha(20)
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: isSelected ? AppTheme.accent : Colors.transparent,
                  width: 3,
                ),
                bottom:
                    const BorderSide(color: AppTheme.borderColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.accent.withAlpha(25)
                        : AppTheme.bgTertiary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(_typeIcon,
                      size: 14,
                      color: isSelected
                          ? AppTheme.accent
                          : AppTheme.textMuted),
                ),
                const SizedBox(width: 10),
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
                GestureDetector(
                  onTap: onToggleVisibility,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      layer.visible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: layer.visible
                          ? AppTheme.textMuted
                          : AppTheme.danger.withValues(alpha:0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddLayerBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _AddLayerBtn({required this.onTap});

  @override
  State<_AddLayerBtn> createState() => _AddLayerBtnState();
}

class _AddLayerBtnState extends State<_AddLayerBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.88).animate(
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.accent.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accent.withAlpha(60)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 14, color: AppTheme.accent),
              SizedBox(width: 2),
              Text('追加',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
