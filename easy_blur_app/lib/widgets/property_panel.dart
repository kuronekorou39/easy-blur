import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/theme.dart';

class PropertyPanel extends StatelessWidget {
  final MosaicLayer? layer;
  final ValueChanged<MosaicType> onTypeChanged;
  final ValueChanged<MosaicShape> onShapeChanged;
  final ValueChanged<double> onIntensityChanged;

  const PropertyPanel({
    super.key,
    required this.layer,
    required this.onTypeChanged,
    required this.onShapeChanged,
    required this.onIntensityChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (layer == null) {
      return const SizedBox.shrink();
    }

    final kf = layer!.keyframes.isNotEmpty ? layer!.keyframes.first : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.bgSecondary,
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'プロパティ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Mosaic type
          const Text('種類', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          Row(
            children: MosaicType.values.map((type) {
              final isSelected = layer!.type == type;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: type != MosaicType.values.last ? 6 : 0,
                  ),
                  child: _OptionChip(
                    label: _typeLabel(type),
                    icon: _typeIcon(type),
                    isSelected: isSelected,
                    onTap: () => onTypeChanged(type),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Shape
          const Text('形状', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          Row(
            children: MosaicShape.values.map((shape) {
              final isSelected = layer!.shape == shape;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: shape != MosaicShape.values.last ? 6 : 0,
                  ),
                  child: _OptionChip(
                    label: _shapeLabel(shape),
                    icon: _shapeIcon(shape),
                    isSelected: isSelected,
                    onTap: () => onShapeChanged(shape),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Intensity
          Row(
            children: [
              const Text('強度', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const Spacer(),
              Text(
                '${(kf?.intensity ?? 20).round()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: AppTheme.bgHover,
              thumbColor: AppTheme.accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackHeight: 3,
              overlayColor: AppTheme.accent.withAlpha(30),
            ),
            child: Slider(
              value: kf?.intensity ?? 20,
              min: 2,
              max: 60,
              onChanged: onIntensityChanged,
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(MosaicType type) {
    switch (type) {
      case MosaicType.pixelate: return 'モザイク';
      case MosaicType.blur: return 'ぼかし';
      case MosaicType.blackout: return '黒塗り';
    }
  }

  IconData _typeIcon(MosaicType type) {
    switch (type) {
      case MosaicType.pixelate: return Icons.grid_on_rounded;
      case MosaicType.blur: return Icons.blur_on_rounded;
      case MosaicType.blackout: return Icons.block_rounded;
    }
  }

  String _shapeLabel(MosaicShape shape) {
    switch (shape) {
      case MosaicShape.rectangle: return '矩形';
      case MosaicShape.ellipse: return '楕円';
    }
  }

  IconData _shapeIcon(MosaicShape shape) {
    switch (shape) {
      case MosaicShape.rectangle: return Icons.crop_square_rounded;
      case MosaicShape.ellipse: return Icons.circle_outlined;
    }
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withAlpha(25)
              : AppTheme.bgTertiary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.borderColor,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.accent : AppTheme.textMuted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppTheme.accent : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
