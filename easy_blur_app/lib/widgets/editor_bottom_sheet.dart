import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'property_panel.dart';
import 'layer_panel.dart';

class EditorBottomSheet extends StatefulWidget {
  final MosaicLayer? selectedLayer;
  final List<MosaicLayer> layers;
  final int selectedIndex;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<double> onIntensityChanged;
  final ValueChanged<int> onSelectLayer;
  final VoidCallback onAddLayer;
  final ValueChanged<int> onDeleteLayer;
  final ValueChanged<int> onToggleVisibility;
  final void Function(int oldIndex, int newIndex) onReorderLayers;

  const EditorBottomSheet({
    super.key,
    required this.selectedLayer,
    required this.layers,
    required this.selectedIndex,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onIntensityChanged,
    required this.onSelectLayer,
    required this.onAddLayer,
    required this.onDeleteLayer,
    required this.onToggleVisibility,
    required this.onReorderLayers,
  });

  @override
  State<EditorBottomSheet> createState() => _EditorBottomSheetState();
}

class _EditorBottomSheetState extends State<EditorBottomSheet> {
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();

  static const double _minExtent = 0.07;
  static const double _midExtent = 0.38;
  static const double _maxExtent = 0.62;

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      initialChildSize: _minExtent,
      minChildSize: _minExtent,
      maxChildSize: _maxExtent,
      snap: true,
      snapSizes: const [_minExtent, _midExtent, _maxExtent],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.sheetRadius),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.sheetBackground.withValues(alpha:0.92),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.sheetRadius),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  // Drag handle
                  SliverToBoxAdapter(child: _buildHandle()),
                  // Property panel
                  SliverToBoxAdapter(
                    child: PropertyPanel(
                      layer: widget.selectedLayer,
                      onTypeChanged: widget.onTypeChanged,
                      onShapeChanged: widget.onShapeChanged,
                      onIntensityChanged: widget.onIntensityChanged,
                    ),
                  ),
                  // Divider
                  const SliverToBoxAdapter(
                    child: Divider(
                      color: AppTheme.borderColor,
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                    ),
                  ),
                  // Layer panel
                  SliverToBoxAdapter(
                    child: LayerPanel(
                      layers: widget.layers,
                      selectedIndex: widget.selectedIndex,
                      onSelect: widget.onSelectLayer,
                      onAdd: widget.onAddLayer,
                      onDelete: widget.onDeleteLayer,
                      onToggleVisibility: widget.onToggleVisibility,
                      onReorder: widget.onReorderLayers,
                    ),
                  ),
                  // Bottom safe area padding
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return GestureDetector(
      onTap: _toggleSheet,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha:0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                if (widget.selectedLayer != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.selectedLayer!.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ] else
                  Text(
                    '${widget.layers.length} レイヤー',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                const Spacer(),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 20,
                  color: AppTheme.textMuted.withValues(alpha:0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSheet() {
    final current = _sheetCtrl.size;
    if (current < (_minExtent + _midExtent) / 2) {
      _sheetCtrl.animateTo(_midExtent,
          duration: AppTheme.animNormal, curve: Curves.easeOutCubic);
    } else if (current < (_midExtent + _maxExtent) / 2) {
      _sheetCtrl.animateTo(_maxExtent,
          duration: AppTheme.animNormal, curve: Curves.easeOutCubic);
    } else {
      _sheetCtrl.animateTo(_minExtent,
          duration: AppTheme.animNormal, curve: Curves.easeOutCubic);
    }
  }
}
