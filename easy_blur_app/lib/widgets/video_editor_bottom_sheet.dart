import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'compact_playback_bar.dart';
import 'timeline_panel.dart';
import 'property_panel.dart';
import 'layer_panel.dart';

class VideoEditorBottomSheet extends StatefulWidget {
  // Playback
  final bool isPlaying;
  final Duration currentTime;
  final Duration totalDuration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;

  // Timeline
  final void Function(int layerIndex) onAddKeyframe;
  final void Function(int layerIndex, int keyframeIndex) onSelectKeyframe;
  final void Function(int layerIndex, int keyframeIndex) onDeleteKeyframe;

  // Property
  final MosaicLayer? selectedLayer;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<double> onIntensityChanged;

  // Layer
  final List<MosaicLayer> layers;
  final int selectedIndex;
  final ValueChanged<int> onSelectLayer;
  final VoidCallback onAddLayer;
  final ValueChanged<int> onDeleteLayer;
  final ValueChanged<int> onToggleVisibility;
  final void Function(int oldIndex, int newIndex) onReorderLayers;

  const VideoEditorBottomSheet({
    super.key,
    required this.isPlaying,
    required this.currentTime,
    required this.totalDuration,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onAddKeyframe,
    required this.onSelectKeyframe,
    required this.onDeleteKeyframe,
    required this.selectedLayer,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onIntensityChanged,
    required this.layers,
    required this.selectedIndex,
    required this.onSelectLayer,
    required this.onAddLayer,
    required this.onDeleteLayer,
    required this.onToggleVisibility,
    required this.onReorderLayers,
  });

  @override
  State<VideoEditorBottomSheet> createState() =>
      _VideoEditorBottomSheetState();
}

class _VideoEditorBottomSheetState extends State<VideoEditorBottomSheet> {
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();

  static const double _minExtent = 0.09;
  static const double _midExtent = 0.35;
  static const double _maxExtent = 0.65;

  @override
  void dispose() {
    _sheetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      initialChildSize: _midExtent,
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
                color: AppTheme.sheetBackground.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.sheetRadius),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
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
                  // Playback bar
                  SliverToBoxAdapter(
                    child: CompactPlaybackBar(
                      isPlaying: widget.isPlaying,
                      currentTime: widget.currentTime,
                      totalDuration: widget.totalDuration,
                      onTogglePlay: widget.onTogglePlay,
                      onSeek: widget.onSeek,
                    ),
                  ),
                  // Timeline
                  SliverToBoxAdapter(
                    child: TimelinePanel(
                      layers: widget.layers,
                      selectedLayerIndex: widget.selectedIndex,
                      currentTime: widget.currentTime,
                      totalDuration: widget.totalDuration,
                      onSeek: widget.onSeek,
                      onAddKeyframe: widget.onAddKeyframe,
                      onSelectKeyframe: widget.onSelectKeyframe,
                      onDeleteKeyframe: widget.onDeleteKeyframe,
                    ),
                  ),
                  // Divider
                  const SliverToBoxAdapter(
                    child: Divider(
                        color: AppTheme.borderColor,
                        height: 1,
                        indent: 16,
                        endIndent: 16),
                  ),
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
                        endIndent: 16),
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
                      onTypeChanged: widget.onTypeChanged,
                      onShapeChanged: widget.onShapeChanged,
                      onInvertedChanged: (_) {},
                      onIntensityChanged: widget.onIntensityChanged,
                    ),
                  ),
                  // Bottom safe area
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
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
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
